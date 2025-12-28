import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/color_category.dart';
import '../models/event.dart';
import '../models/experience.dart';
import '../models/message_thread.dart';
import '../models/message_thread_participant.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import '../services/event_service.dart';
import '../services/experience_service.dart';
import '../services/message_service.dart';
import '../config/colors.dart';
import '../widgets/cached_profile_avatar.dart';
import '../widgets/event_editor_modal.dart';
import '../widgets/shared_media_preview_modal.dart';
import 'experience_page_screen.dart';
import 'public_profile_screen.dart';
import 'share_preview_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';

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
  late final ExperienceService _experienceService;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _titleFocusNode = FocusNode();
  bool _sending = false;
  bool _isEditingTitle = false;
  bool _isSavingTitle = false;

  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];
  Future<void>? _userCollectionsFuture;

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
    _experienceService = ExperienceService();

    // Mark thread as read when opened
    _messageService.markThreadAsRead(widget.thread.id, widget.currentUserId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _titleController.dispose();
    _scrollController.dispose();
    _titleFocusNode.dispose();
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
    // With reverse: true on ListView, position 0 is the bottom (newest messages)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleBackPressed() {
    Navigator.of(context).pop();
  }

  void _openPublicProfile(String userId) {
    if (!mounted || userId.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: userId),
      ),
    );
  }

  void _copyShareLinkToClipboard(String url, String itemType) {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$itemType link copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _startEditingTitle(String title) {
    if (_isSavingTitle) {
      return;
    }
    _titleController
      ..text = title
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: title.length),
      );
    setState(() {
      _isEditingTitle = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _titleFocusNode.requestFocus();
      }
    });
  }

  void _stopEditingTitle() {
    if (!_isEditingTitle) {
      return;
    }
    _titleFocusNode.unfocus();
    if (mounted) {
      setState(() {
        _isEditingTitle = false;
      });
    }
  }

  Future<void> _saveThreadTitle(MessageThread thread) async {
    if (!_isEditingTitle || _isSavingTitle) {
      return;
    }

    final newTitle = _titleController.text.trim();
    final currentCustomTitle = thread.title?.trim();
    final defaultTitle = _buildDefaultTitle(thread);

    final bool isUnchangedCustom =
        currentCustomTitle != null && newTitle == currentCustomTitle;
    final bool isNoOpDefault = currentCustomTitle == null &&
        (newTitle.isEmpty || newTitle == defaultTitle);

    if (isUnchangedCustom || isNoOpDefault) {
      _stopEditingTitle();
      return;
    }

    setState(() {
      _isSavingTitle = true;
    });

    if (mounted) {
      FocusScope.of(context).unfocus();
    }

    try {
      await _messageService.updateThreadTitle(
        threadId: thread.id,
        title: newTitle,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSavingTitle = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update chat name: $error')),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingTitle = false;
      _isEditingTitle = false;
    });
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
          backgroundColor: AppColors.backgroundColorDark,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColorDark,
            foregroundColor: Colors.black,
            leading: BackButton(onPressed: _handleBackPressed),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isEditingTitle
                  ? SizedBox(
                      key: const ValueKey('editingTitleField'),
                      height: 40,
                      child: Focus(
                        onFocusChange: (hasFocus) {
                          if (!hasFocus) {
                            _saveThreadTitle(thread);
                          }
                        },
                        child: TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          autofocus: true,
                          enabled: !_isSavingTitle,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Name this chat',
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          onSubmitted: (_) => _saveThreadTitle(thread),
                        ),
                      ),
                    )
                  : GestureDetector(
                      key: const ValueKey('displayTitle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: withHeavyTap(() => _startEditingTitle(title)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
            ),
            actions: [
              if (_isEditingTitle)
                IconButton(
                  icon: _isSavingTitle
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  onPressed:
                      _isSavingTitle ? null : () => _saveThreadTitle(thread),
                ),
              IconButton(
                icon: const Icon(
                  Icons.people,
                  color: Colors.black,
                ),
                tooltip: 'Chat members',
                onPressed: () => _showParticipantsDialog(thread),
              ),
            ],
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

                    // Use reverse: true so the list starts at the bottom
                    // and new messages appear at the bottom naturally
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        // Since reverse is true, we need to reverse the index
                        // to display messages in chronological order (oldest at top)
                        final reversedIndex = messages.length - 1 - index;
                        final message = messages[reversedIndex];
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
    // For profile share messages, use a special card layout
    if (message.isProfileShare) {
      return _buildProfileShareCard(message, isMine, sender);
    }
    
    // For multi-experience share messages, use a special card layout
    if (message.isMultiExperienceShare) {
      return _buildMultiExperienceShareCard(message, isMine, sender);
    }
    
    // For multi-category share messages, use a special card layout
    if (message.isMultiCategoryShare) {
      return _buildMultiCategoryShareCard(message, isMine, sender);
    }
    
    // For category share messages, use a special card layout
    if (message.isCategoryShare) {
      return _buildCategoryShareCard(message, isMine, sender);
    }
    
    // For event share messages, use a special card layout
    if (message.isEventShare) {
      return _buildEventShareCard(message, isMine, sender);
    }
    
    // For single experience share messages, use a special card layout
    if (message.isExperienceShare) {
      return _buildExperienceShareCard(message, isMine, sender);
    }

    // Regular text message bubble
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        isMine ? Theme.of(context).primaryColor : Colors.grey.shade400;
    final textColor = isMine ? Colors.white : Colors.black87;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;

    final bubble = Container(
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
    );

    final bubbleWithConstraints = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: bubble,
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: bubbleWithConstraints,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: bubbleWithConstraints),
        ],
      ),
    );
  }


  Widget _buildProfileShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshot = message.profileSnapshot;

    if (snapshot == null) {
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Shared a profile'),
        ),
      );
    }

    final String userId = snapshot['userId'] as String? ?? '';
    final String? displayName = snapshot['displayName'] as String?;
    final String? username = snapshot['username'] as String?;
    final String? photoURL = snapshot['photoURL'] as String?;
    final String? bio = snapshot['bio'] as String?;

    // Determine what name to show
    final String profileName = displayName?.isNotEmpty == true
        ? displayName!
        : (username?.isNotEmpty == true ? '@$username' : 'Plendy User');
    final String? subtitleText = displayName?.isNotEmpty == true && username?.isNotEmpty == true
        ? '@$username'
        : null;

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              child: Text(
                '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared a profile',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          Card(
            elevation: 2,
            color: isMine
                ? Theme.of(context).primaryColor
                : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: withHeavyTap(() => _openPublicProfile(userId)),
              onLongPress: () => _copyShareLinkToClipboard(
                'https://plendy.app/profile/$userId',
                'Profile',
              ),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with profile picture
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: CachedProfileAvatar(
                        photoUrl: photoURL,
                        radius: 40,
                        fallbackText: profileName.isNotEmpty
                            ? profileName[0].toUpperCase()
                            : '?',
                      ),
                    ),
                  ),
                  // Profile info
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          'Shared Profile',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? Colors.white70
                                : Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profileName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (bio != null && bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            bio,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view profile. Hold to copy link.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: card,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
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
        child: const Text('Shared an experience'),
      ),
    );
  }

  final experienceName = snapshot['name'] as String? ?? 'Experience';
  final locationData = snapshot['location'] as Map<String, dynamic>?;

  // Check if this is a discovery preview share (has highlightedMediaUrl)
  final highlightedMediaUrl = snapshot['highlightedMediaUrl'] as String?;
  final isDiscoveryPreview =
      highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty;

  // Use highlighted media URL for discovery shares, otherwise use the main image
  final imageUrl = isDiscoveryPreview
      ? highlightedMediaUrl
      : (snapshot['image'] as String?);

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

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          color: isMine
              ? Theme.of(context).primaryColor
              : Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              InkWell(
                onLongPress: message.shareId != null && message.shareId!.isNotEmpty
                    ? () => _copyShareLinkToClipboard(
                          'https://plendy.app/shared/${message.shareId}',
                          'Experience',
                        )
                    : null,
                onTap: withHeavyTap(() async {
                  if (isDiscoveryPreview) {
                    // Discovery preview: show media preview modal
                    await _showMediaPreviewModal(
                      experienceName: experienceName,
                      mediaUrl: highlightedMediaUrl,
                      experienceSnapshot: snapshot,
                    );
                  } else {
                    // Full experience share: open experience directly
                    final experience = Experience(
                      id: snapshot['id'] as String? ??
                          'preview_${DateTime.now().millisecondsSinceEpoch}',
                      name: experienceName,
                      description: snapshot['description'] as String? ?? '',
                      location: Location.fromMap(
                          snapshot['location'] as Map<String, dynamic>? ??
                              {}),
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      editorUserIds:
                          (snapshot['editorUserIds'] as List<dynamic>?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [],
                      createdBy: snapshot['createdBy'] as String?,
                      sharedMediaItemIds:
                          (snapshot['sharedMediaItemIds'] as List<dynamic>?)
                                  ?.cast<String>() ??
                              [],
                    );

                    // Build media items from mediaUrls in snapshot for public content
                    final mediaUrls =
                        (snapshot['mediaUrls'] as List<dynamic>?)
                                ?.cast<String>() ??
                            [];
                    final List<SharedMediaItem> fullExperienceMediaItems = [];

                    if (mediaUrls.isNotEmpty) {
                      for (int i = 0; i < mediaUrls.length; i++) {
                        fullExperienceMediaItems.add(SharedMediaItem(
                          id: 'preview_${experience.id}_$i',
                          path: mediaUrls[i],
                          createdAt: DateTime.now().subtract(
                              Duration(seconds: mediaUrls.length - i)),
                          ownerUserId: 'public_discovery',
                          experienceIds: [],
                        ));
                      }
                    }

                    await _handleViewExperience(
                        experience, snapshot, fullExperienceMediaItems);
                  }
                }),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      if (isDiscoveryPreview)
                        GestureDetector(
                          onTap: withHeavyTap(() => _openLink(Uri.parse(imageUrl))),
                          child: Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(
                                    _getMediaIcon(imageUrl),
                                    size: 56,
                                    color: _getMediaIconColor(imageUrl),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Open in ${_getMediaLabel(imageUrl)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _getMediaIconColor(imageUrl),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: Image.network(
                            imageUrl,
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
                          ),
                        ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Text(
                            isDiscoveryPreview ? 'Shared Discovery' : 'Shared Experience',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  experienceName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isMine
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: isMine ? Colors.white : Colors.grey,
                              ),
                            ],
                          ),
                          if (locationText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 14,
                                  color:
                                      isMine ? Colors.white : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    locationText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isMine
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  if (isMine) {
    return Align(
      alignment: alignment,
      child: card,
    );
  }

  final avatarParticipant =
      sender ?? MessageThreadParticipant(id: message.senderId);

  return Align(
    alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
    ),
  );
}

  Widget _buildMultiExperienceShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshots = message.experienceSnapshots;

    if (snapshots == null || snapshots.isEmpty) {
      // Fallback if snapshots are missing
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Shared multiple experiences'),
        ),
      );
    }

    final int count = snapshots.length;
    
    // Get the first 3 experience names for preview
    final previewNames = snapshots
        .take(3)
        .map((s) {
          final snap = s['snapshot'] as Map<String, dynamic>?;
          return snap?['name'] as String? ?? 'Experience';
        })
        .toList();
    
    // Get first experience's image for the card thumbnail
    String? thumbnailUrl;
    String? firstIcon;
    Color? firstColor;
    for (final s in snapshots) {
      final snap = s['snapshot'] as Map<String, dynamic>?;
      if (snap != null) {
        // Try to get category icon and color
        firstIcon ??= snap['categoryIconDenorm'] as String?;
        final colorHex = snap['colorHexDenorm'] as String?;
        if (colorHex != null && firstColor == null) {
          firstColor = _parseColorHex(colorHex);
        }
        // Try to get image
        final image = snap['image'] as String?;
        if (image != null && image.isNotEmpty && thumbnailUrl == null) {
          thumbnailUrl = image;
        }
      }
    }

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              child: Text(
                '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared $count experiences',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          Card(
            elevation: 2,
            color: isMine
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: withHeavyTap(() => _openMultiExperiencePreview(message.shareId, snapshots, message.senderId)),
              onLongPress: message.shareId != null && message.shareId!.isNotEmpty
                  ? () => _copyShareLinkToClipboard(
                        'https://plendy.app/shared/${message.shareId}',
                        'Experiences',
                      )
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail/icon header
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Show icon or count badge
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              firstIcon ?? '📍',
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Count badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '$count experiences',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Experience names preview
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          'Shared Experiences',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? Colors.white70
                                : Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count experiences',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...previewNames.map((name) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isMine
                                        ? Colors.white70
                                        : Colors.grey.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
                        if (count > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+ ${count - 3} more',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view all. Hold to copy link.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: card,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
      ),
    );
  }

  Color? _parseColorHex(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return null;
    try {
      String normalized = colorHex.toUpperCase().replaceAll('#', '');
      if (normalized.length == 6) {
        normalized = 'FF$normalized';
      }
      if (normalized.length == 8) {
        return Color(int.parse('0x$normalized'));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Widget _buildCategoryShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshot = message.categorySnapshot;

    if (snapshot == null) {
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Shared a category'),
        ),
      );
    }

    final String categoryName = snapshot['name'] as String? ?? 'Category';
    final String? icon = snapshot['icon'] as String?;
    final int? colorValue = snapshot['color'] as int?;
    final String categoryType = snapshot['categoryType'] as String? ?? 'user';
    final String accessMode = snapshot['accessMode'] as String? ?? 'view';
    final List<dynamic> experiences = snapshot['experiences'] as List<dynamic>? ?? [];
    final int experienceCount = experiences.length;

    // Determine display color
    Color displayColor;
    if (colorValue != null) {
      displayColor = Color(colorValue);
    } else {
      displayColor = Theme.of(context).primaryColor;
    }

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              child: Text(
                '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared a category',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          Card(
            elevation: 2,
            color: isMine ? Theme.of(context).primaryColor : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: withHeavyTap(() => _openCategoryPreview(message.shareId, snapshot)),
              onLongPress: message.shareId != null && message.shareId!.isNotEmpty
                  ? () => _copyShareLinkToClipboard(
                        'https://plendy.app/shared-category/${message.shareId}',
                        'Category',
                      )
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with category icon/color
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: categoryType == 'color'
                          ? Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: displayColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            )
                          : Text(
                              icon ?? '📁',
                              style: const TextStyle(fontSize: 40),
                            ),
                    ),
                  ),
                  // Category info
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          categoryType == 'color' ? 'Shared Color Category' : 'Shared Category',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? Colors.white70
                                : Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          categoryName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$experienceCount experience${experienceCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              accessMode == 'edit' ? Icons.edit_outlined : Icons.visibility_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              accessMode == 'edit' ? 'Edit access' : 'View access',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view. Hold to copy link.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: card,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
      ),
    );
  }

  void _openCategoryPreview(String? shareId, Map<String, dynamic> snapshot) {
    // For now, show a snackbar indicating this feature is coming
    // In the future, this could navigate to a category preview screen
    final String categoryName = snapshot['name'] as String? ?? 'Category';
    final List<dynamic> experiences = snapshot['experiences'] as List<dynamic>? ?? [];
    
    if (experiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$categoryName" has no experiences to show')),
      );
      return;
    }

    // Convert experiences to the format expected by SharePreviewScreen
    final List<Map<String, dynamic>> experienceSnapshots = experiences
        .whereType<Map<String, dynamic>>()
        .map((exp) => {
              'experienceId': exp['experienceId'] ?? '',
              'snapshot': exp,
            })
        .toList();

    // Navigate to SharePreviewScreen with the experiences from the category
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharePreviewScreen(
          token: shareId ?? '',
          preloadedSnapshots: experienceSnapshots,
          preloadedFromUserId: widget.thread.participantIds.firstWhere(
            (id) => id != widget.currentUserId,
            orElse: () => '',
          ),
        ),
      ),
    );
  }

  void _openMultiExperiencePreview(
    String? shareId,
    List<Map<String, dynamic>> snapshots,
    String senderId,
  ) {
    if (snapshots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open shared experiences')),
      );
      return;
    }
    
    // Navigate to SharePreviewScreen with pre-loaded snapshots
    // This avoids the need to fetch from Firestore again
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharePreviewScreen(
          token: shareId ?? '',
          preloadedSnapshots: snapshots,
          preloadedFromUserId: senderId,
        ),
      ),
    );
  }

  Widget _buildMultiCategoryShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshots = message.categorySnapshots;

    if (snapshots == null || snapshots.isEmpty) {
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Shared multiple categories'),
        ),
      );
    }

    final int count = snapshots.length;
    
    // Get the first 3 category names for preview
    final previewNames = snapshots
        .take(3)
        .map((s) => s['name'] as String? ?? 'Category')
        .toList();
    
    // Get first category's icon/color for the card header
    String? firstIcon;
    Color? firstColor;
    for (final s in snapshots) {
      firstIcon ??= s['icon'] as String?;
      final colorValue = s['color'] as int?;
      if (colorValue != null && firstColor == null) {
        firstColor = Color(colorValue);
      }
      if (firstIcon != null && firstColor != null) break;
    }

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              child: Text(
                '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared $count categories',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          Card(
            elevation: 2,
            color: isMine
                ? Theme.of(context).primaryColor
                : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: withHeavyTap(() => _openMultiCategoryPreview(message.shareId, snapshots)),
              onLongPress: message.shareId != null && message.shareId!.isNotEmpty
                  ? () => _copyShareLinkToClipboard(
                        'https://plendy.app/shared-category/${message.shareId}',
                        'Categories',
                      )
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with category icons
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Show icon or category badge
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              firstIcon ?? '📁',
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Count badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '$count categories',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Category names preview
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          'Shared Categories',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? Colors.white70
                                : Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count categories',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...previewNames.map((name) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 14,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isMine
                                        ? Colors.white70
                                        : Colors.grey.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
                        if (count > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+ ${count - 3} more',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view all. Hold to copy link.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: card,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
      ),
    );
  }

  void _openMultiCategoryPreview(String? shareId, List<Map<String, dynamic>> snapshots) {
    if (snapshots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No categories to display')),
      );
      return;
    }

    // Combine all experiences from all categories
    final List<Map<String, dynamic>> allExperiences = [];
    for (final categorySnapshot in snapshots) {
      final experiences = categorySnapshot['experiences'] as List<dynamic>? ?? [];
      for (final exp in experiences) {
        if (exp is Map<String, dynamic>) {
          allExperiences.add({
            'experienceId': exp['experienceId'] ?? '',
            'snapshot': exp,
          });
        }
      }
    }

    if (allExperiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No experiences in the shared categories')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharePreviewScreen(
          token: shareId ?? '',
          preloadedSnapshots: allExperiences,
          preloadedFromUserId: widget.thread.participantIds.firstWhere(
            (id) => id != widget.currentUserId,
            orElse: () => '',
          ),
        ),
      ),
    );
  }

  Widget _buildEventShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshot = message.eventSnapshot;

    if (snapshot == null) {
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Shared an event'),
        ),
      );
    }

    final String eventName = snapshot['name'] as String? ?? 'Event';
    final String? eventDescription = snapshot['description'] as String?;
    final String? startDateStr = snapshot['startDate'] as String?;
    final String? endDateStr = snapshot['endDate'] as String?;
    final List<dynamic> experiences = snapshot['experiences'] as List<dynamic>? ?? [];
    final int experienceCount = experiences.length;

    // Parse date for display
    String dateDisplay = '';
    if (startDateStr != null) {
      try {
        final startDate = DateTime.parse(startDateStr);
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        dateDisplay = '${months[startDate.month - 1]} ${startDate.day}, ${startDate.year}';
        if (endDateStr != null && endDateStr != startDateStr) {
          final endDate = DateTime.parse(endDateStr);
          dateDisplay += ' - ${months[endDate.month - 1]} ${endDate.day}, ${endDate.year}';
        }
      } catch (_) {
        // Keep dateDisplay empty if parsing fails
      }
    }

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              child: Text(
                '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared an event',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          Card(
            elevation: 2,
            color: isMine
                ? Theme.of(context).primaryColor
                : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: withHeavyTap(() => _openEventPreview(message.shareId, snapshot)),
              onLongPress: () {
                // Use shareToken from event snapshot if available
                final String? shareToken = snapshot['shareToken'] as String?;
                if (shareToken != null && shareToken.isNotEmpty) {
                  _copyShareLinkToClipboard(
                    'https://plendy.app/shared-event/$shareToken',
                    'Event',
                  );
                } else if (message.shareId != null && message.shareId!.isNotEmpty) {
                  _copyShareLinkToClipboard(
                    'https://plendy.app/shared-event/${message.shareId}',
                    'Event',
                  );
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with calendar icon
                  Container(
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade300,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.event,
                          size: 32,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ),
                  // Event info
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          'Shared Event',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine
                                ? Colors.white70
                                : Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          eventName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMine ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dateDisplay.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  dateDisplay,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isMine
                                        ? Colors.white70
                                        : Colors.grey.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (eventDescription != null && eventDescription.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            eventDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$experienceCount experience${experienceCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view. Hold to copy link.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: alignment,
        child: card,
      );
    }

    final avatarParticipant =
        sender ?? MessageThreadParticipant(id: message.senderId);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildParticipantAvatar(
            avatarParticipant,
            size: 34,
            onTap: withHeavyTap(() => _openPublicProfile(avatarParticipant.id)),
          ),
          const SizedBox(width: 8),
          Flexible(child: card),
        ],
      ),
    );
  }

  void _openEventPreview(String? shareId, Map<String, dynamic> snapshot) async {
    final String eventId = snapshot['eventId'] as String? ?? '';
    final String shareToken = snapshot['shareToken'] as String? ?? '';

    if (eventId.isEmpty && shareToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load event')),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading event...'),
          ],
        ),
      ),
    );

    try {
      final eventService = EventService();
      final experienceService = ExperienceService();

      // Get the event by ID or share token
      Event? event;
      if (shareToken.isNotEmpty) {
        event = await eventService.getEventByShareToken(shareToken);
      } else if (eventId.isNotEmpty) {
        event = await eventService.getEvent(eventId);
      }

      if (event == null) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event not found')),
          );
        }
        return;
      }

      // Get experiences and categories
      final experienceIds = event.experiences
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();

      List<Experience> experiences = [];
      if (experienceIds.isNotEmpty) {
        experiences = await experienceService.getExperiencesByIds(experienceIds);
      }

      // Fetch the planner's categories for proper category icon display
      List<UserCategory> categories = [];
      List<ColorCategory> colorCategories = [];

      // Collect all category IDs from experiences and event entries
      final Set<String> categoryIds = {};
      final Set<String> colorCategoryIds = {};

      for (final exp in experiences) {
        if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
          categoryIds.add(exp.categoryId!);
        }
        categoryIds.addAll(exp.otherCategories.where((id) => id.isNotEmpty));

        if (exp.colorCategoryId != null && exp.colorCategoryId!.isNotEmpty) {
          colorCategoryIds.add(exp.colorCategoryId!);
        }
        colorCategoryIds.addAll(exp.otherColorCategoryIds.where((id) => id.isNotEmpty));
      }

      for (final entry in event.experiences) {
        if (entry.inlineCategoryId != null && entry.inlineCategoryId!.isNotEmpty) {
          categoryIds.add(entry.inlineCategoryId!);
        }
        categoryIds.addAll(entry.inlineOtherCategoryIds.where((id) => id.isNotEmpty));

        if (entry.inlineColorCategoryId != null && entry.inlineColorCategoryId!.isNotEmpty) {
          colorCategoryIds.add(entry.inlineColorCategoryId!);
        }
        colorCategoryIds.addAll(entry.inlineOtherColorCategoryIds.where((id) => id.isNotEmpty));
      }

      // Fetch the planner's categories by IDs
      try {
        if (categoryIds.isNotEmpty) {
          categories = await experienceService.getUserCategoriesByOwnerAndIds(
            event.plannerUserId,
            categoryIds.toList(),
          );
        }
      } catch (e) {
        debugPrint('ChatScreen: Failed to fetch planner categories for event ${event.id}: $e');
      }

      try {
        if (colorCategoryIds.isNotEmpty) {
          colorCategories = await experienceService.getColorCategoriesByOwnerAndIds(
            event.plannerUserId,
            colorCategoryIds.toList(),
          );
        }
      } catch (e) {
        debugPrint('ChatScreen: Failed to fetch planner color categories for event ${event.id}: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close loading

        // Navigate to EventEditorModal in read-only mode
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventEditorModal(
              event: event!,
              experiences: experiences,
              categories: categories,
              colorCategories: colorCategories,
              isReadOnly: true, // View-only mode
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading event: $e')),
        );
      }
    }
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
          color: AppColors.backgroundColor,
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
    final customTitle = thread.title?.trim();
    if (customTitle != null && customTitle.isNotEmpty) {
      return customTitle;
    }
    return _buildDefaultTitle(thread);
  }

  String _buildDefaultTitle(MessageThread thread) {
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

  Future<void> _showParticipantsDialog(MessageThread thread) async {
    final participants = thread.participantIds
        .map(
          (id) => thread.participant(id) ?? MessageThreadParticipant(id: id),
        )
        .toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(dialogContext).size.height * 0.6;
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Chat Members'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: participants.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final participant = participants[index];
                  final displayName =
                      participant.displayName?.isNotEmpty == true
                          ? participant.displayName!
                          : participant.displayLabel(fallback: 'Friend');
                  final username = participant.username?.isNotEmpty == true
                      ? '@${participant.username!}'
                      : null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _buildParticipantAvatar(participant),
                    title: Text(displayName),
                    subtitle: username != null && username != displayName
                        ? Text(username)
                        : null,
                    onTap: withHeavyTap(() {
                      Navigator.of(dialogContext).pop();
                      _openPublicProfile(participant.id);
                    }),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildParticipantAvatar(
    MessageThreadParticipant participant, {
    double size = 40,
    VoidCallback? onTap,
  }) {
    final label = participant.displayLabel(fallback: 'Friend').trim();
    final sanitized = label.replaceAll('@', '').trim();
    final initialSource = sanitized.isNotEmpty ? sanitized : label;
    final initial =
        initialSource.isNotEmpty ? initialSource[0].toUpperCase() : '?';

    return _wrapAvatar(
      CachedProfileAvatar(
        photoUrl: participant.photoUrl,
        radius: size / 2,
        fallbackText: initial,
      ),
      onTap,
    );
  }

  Widget _wrapAvatar(Widget avatar, VoidCallback? onTap) {
    if (onTap == null) {
      return avatar;
    }

    return GestureDetector(
      onTap: withHeavyTap(onTap),
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }

  Future<void> _showMediaPreviewModal({
    required String experienceName,
    required String? mediaUrl,
    required Map<String, dynamic> experienceSnapshot,
  }) async {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media available to preview')),
      );
      return;
    }

    // Check if the current user owns or has edit access to the experience
    final currentUserId = widget.currentUserId;
    final createdBy = experienceSnapshot['createdBy'] as String?;
    final editorUserIds = experienceSnapshot['editorUserIds'] as List<dynamic>?;

    final bool hasAccess = createdBy == currentUserId ||
        (editorUserIds != null && editorUserIds.contains(currentUserId));

    // Create a minimal Experience object for the preview modal
    final experience = Experience(
      id: experienceSnapshot['id'] as String? ??
          'preview_${DateTime.now().millisecondsSinceEpoch}',
      name: experienceName,
      description: experienceSnapshot['description'] as String? ?? '',
      location: Location.fromMap(
          experienceSnapshot['location'] as Map<String, dynamic>? ?? {}),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      editorUserIds: editorUserIds?.map((e) => e.toString()).toList() ?? [],
      createdBy: createdBy,
      sharedMediaItemIds:
          (experienceSnapshot['sharedMediaItemIds'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],
    );

    // Build media items from the snapshot
    // For discovery previews, use mediaUrls from the snapshot
    final mediaUrls =
        (experienceSnapshot['mediaUrls'] as List<dynamic>?)?.cast<String>() ??
            [];
    final List<SharedMediaItem> mediaItems = [];

    if (mediaUrls.isNotEmpty) {
      // Build SharedMediaItems from the URLs in the snapshot
      for (int i = 0; i < mediaUrls.length; i++) {
        mediaItems.add(SharedMediaItem(
          id: 'preview_${experience.id}_$i',
          path: mediaUrls[i],
          createdAt:
              DateTime.now().subtract(Duration(seconds: mediaUrls.length - i)),
          ownerUserId: 'public_discovery',
          experienceIds: [],
        ));
      }
    } else {
      // Fallback: create a single media item from the highlighted URL
      mediaItems.add(SharedMediaItem(
        id: 'preview_${DateTime.now().millisecondsSinceEpoch}',
        path: mediaUrl,
        createdAt: DateTime.now(),
        ownerUserId: currentUserId,
        experienceIds: [],
      ));
    }

    // Find the media item that matches the highlighted URL
    final mediaItem = mediaItems.firstWhere(
      (item) => item.path == mediaUrl,
      orElse: () => mediaItems.first,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (modalContext) {
        return SharedMediaPreviewModal(
          experience: experience,
          mediaItem: mediaItem,
          mediaItems: mediaItems, // Pass all media items
          onLaunchUrl: (url) => _openLink(Uri.parse(url)),
          category: null,
          userColorCategories: const [],
          showSavedDate: hasAccess, // Only show saved date if user has access
          onViewExperience: () =>
              _handleViewExperience(experience, experienceSnapshot, mediaItems),
        );
      },
    );
  }

  Future<void> _handleViewExperience(
    Experience experience,
    Map<String, dynamic> snapshot,
    List<SharedMediaItem> mediaItems,
  ) async {
    // Extract place ID from snapshot
    final locationData = snapshot['location'] as Map<String, dynamic>?;
    final String? placeId = locationData?['placeId'] as String?;

    // Try to find if user has an editable experience at this place
    Experience? editableExperience;
    if (placeId != null && placeId.isNotEmpty) {
      editableExperience =
          await _experienceService.findEditableExperienceByPlaceId(placeId);
    }

    if (!mounted) return;

    if (editableExperience != null) {
      // User has an editable experience at this place
      await _openEditableExperience(editableExperience);
    } else {
      // No editable experience - show as read-only with media items
      await _openReadOnlyExperience(experience, snapshot, mediaItems);
    }
  }

  Future<void> _openEditableExperience(Experience experience) async {
    await _ensureUserCollectionsLoaded();
    final UserCategory category = _resolveCategoryForExperience(experience);
    final List<ColorCategory> colorCategories = _userColorCategories.isEmpty
        ? const <ColorCategory>[]
        : _userColorCategories;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: colorCategories,
        ),
      ),
    );
  }

  Future<void> _openReadOnlyExperience(
    Experience experience,
    Map<String, dynamic> snapshot,
    List<SharedMediaItem> mediaItems,
  ) async {
    // Create a read-only category
    const readOnlyCategory = UserCategory(
      id: 'shared_readonly_category',
      name: 'Shared',
      icon: '🔗',
      ownerUserId: 'shared',
    );

    // Get sharedMediaItemIds from the snapshot
    final sharedMediaItemIds =
        (snapshot['sharedMediaItemIds'] as List<dynamic>?)?.cast<String>() ??
            [];

    // Create an experience with the sharedMediaItemIds so the content tab can load them
    final experienceWithMedia = experience.copyWith(
      sharedMediaItemIds: sharedMediaItemIds,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: experienceWithMedia,
          category: readOnlyCategory,
          userColorCategories: const <ColorCategory>[],
          initialMediaItems: mediaItems.isNotEmpty
              ? mediaItems
              : null, // Pass media items for public content
          readOnlyPreview: true,
        ),
      ),
    );
  }

  Future<void> _ensureUserCollectionsLoaded() {
    if (_userCollectionsFuture != null) {
      return _userCollectionsFuture!;
    }
    _userCollectionsFuture = _loadUserCollections().whenComplete(() {
      _userCollectionsFuture = null;
    });
    return _userCollectionsFuture!;
  }

  Future<void> _loadUserCollections() async {
    try {
      final categories = await _experienceService.getUserCategories(
        includeSharedEditable: true,
      );
      final colorCategories = await _experienceService.getUserColorCategories(
        includeSharedEditable: true,
      );
      if (mounted) {
        setState(() {
          _userCategories = categories;
          _userColorCategories = colorCategories;
        });
      }
    } catch (e) {
      debugPrint('ChatScreen: Failed to load user collections: $e');
    }
  }

  UserCategory _resolveCategoryForExperience(Experience experience) {
    if (experience.categoryId != null) {
      for (final category in _userCategories) {
        if (category.id == experience.categoryId) {
          return category;
        }
      }
    }

    final bool isUncategorized =
        experience.categoryId == null || experience.categoryId!.isEmpty;

    return UserCategory(
      id: experience.categoryId ?? 'uncategorized',
      name: isUncategorized ? 'Uncategorized' : 'Collection',
      icon: '📍',
      ownerUserId: experience.createdBy ?? 'system_default',
    );
  }

  IconData _getMediaIcon(String url) {
    if (url.contains('tiktok.com')) return FontAwesomeIcons.tiktok;
    if (url.contains('instagram.com')) return FontAwesomeIcons.instagram;
    if (url.contains('facebook.com')) return FontAwesomeIcons.facebook;
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return FontAwesomeIcons.youtube;
    }
    return Icons.link;
  }

  String _getMediaLabel(String url) {
    if (url.contains('tiktok.com')) return 'TikTok';
    if (url.contains('instagram.com')) return 'Instagram';
    if (url.contains('facebook.com')) return 'Facebook';
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return 'YouTube';
    }
    return 'Browser';
  }

  Color _getMediaIconColor(String url) {
    if (url.contains('tiktok.com')) return const Color(0xFF000000); // Black
    if (url.contains('instagram.com')) {
      return const Color(0xFFE4405F); // Instagram gradient (using primary pink)
    }
    if (url.contains('facebook.com')) {
      return const Color(0xFF1877F2); // Facebook blue
    }
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return const Color(0xFFFF0000); // YouTube red
    }
    return Colors.grey.shade600; // Generic link color
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
