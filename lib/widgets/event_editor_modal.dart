import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/event.dart';
import '../models/experience.dart';
import '../models/user_profile.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../services/event_service.dart';
import '../services/experience_service.dart';
import '../services/auth_service.dart';
import '../services/google_maps_service.dart';
import '../services/event_notification_queue_service.dart';
import '../widgets/shared_media_preview_modal.dart';
import '../screens/event_experience_selector_screen.dart';
import '../screens/location_picker_screen.dart';
import '../screens/experience_page_screen.dart';
import '../screens/map_screen.dart';
import '../screens/events_screen.dart';
import 'share_experience_bottom_sheet.dart';

class EventEditorResult {
  final Event? savedEvent;
  final Event? draftEvent;
  final bool wasSaved;

  const EventEditorResult({
    this.savedEvent,
    this.draftEvent,
    this.wasSaved = false,
  });
}

/// Full-screen modal for editing event details
class EventEditorModal extends StatefulWidget {
  final Event event;
  final List<Experience> experiences; // Resolved experiences for the event
  final List<UserCategory> categories;
  final List<ColorCategory> colorCategories;
  final bool returnToSelectorOnItineraryTap;

  const EventEditorModal({
    super.key,
    required this.event,
    required this.experiences,
    required this.categories,
    required this.colorCategories,
    this.returnToSelectorOnItineraryTap = false,
  });

  @override
  State<EventEditorModal> createState() => _EventEditorModalState();
}

class _EventEditorModalState extends State<EventEditorModal> {
  final _eventService = EventService();
  final _experienceService = ExperienceService();
  final _authService = AuthService();
  final _eventNotificationQueueService = EventNotificationQueueService();

  late Event _currentEvent;
  List<Experience> _availableExperiences = [];
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _coverImageUrlController;
  late TextEditingController _capacityController;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  // User profiles cache
  final Map<String, UserProfile> _userProfiles = {};
  final Set<String> _manuallyEditedScheduleIds = {};
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};

  @override
  void initState() {
    super.initState();
    _currentEvent = _eventWithAutoPrimarySchedule(widget.event);
    _availableExperiences = List<Experience>.from(widget.experiences);
    _titleController = TextEditingController(text: _currentEvent.title);
    _descriptionController =
        TextEditingController(text: _currentEvent.description);
    _coverImageUrlController =
        TextEditingController(text: _currentEvent.coverImageUrl ?? '');
    _capacityController = TextEditingController(
      text: _currentEvent.capacity?.toString() ?? '',
    );

    _titleController.addListener(() => _markUnsavedChanges());
    _descriptionController.addListener(() => _markUnsavedChanges());
    _coverImageUrlController.addListener(() => _markUnsavedChanges());
    _capacityController.addListener(() => _markUnsavedChanges());

    _loadUserProfiles();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _coverImageUrlController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _markUnsavedChanges() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  Future<void> _loadUserProfiles() async {
    final userIds = <String>{
      _currentEvent.plannerUserId,
      ..._currentEvent.collaboratorIds,
      ..._currentEvent.invitedUserIds,
    };

    for (final userId in userIds) {
      final profile = await _experienceService.getUserProfileById(userId);
      if (profile != null && mounted) {
        setState(() {
          _userProfiles[userId] = profile;
        });
      }
    }
  }

  Future<void> _saveEvent() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedEvent = _currentEvent.copyWith(
        title: _titleController.text.trim().isEmpty
            ? 'Untitled Event'
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        coverImageUrl: _coverImageUrlController.text.trim().isEmpty
            ? null
            : _coverImageUrlController.text.trim(),
        capacity: _capacityController.text.trim().isEmpty
            ? null
            : int.tryParse(_capacityController.text.trim()),
        updatedAt: DateTime.now(),
      );

      final isNewEvent = _currentEvent.id.isEmpty;
      Event savedEvent;
      if (isNewEvent) {
        // New event - create it
        final eventId = await _eventService.createEvent(updatedEvent);
        savedEvent = updatedEvent.copyWith(id: eventId);
      } else {
        // Existing event - update it
        await _eventService.updateEvent(updatedEvent);
        savedEvent = updatedEvent;
      }

      try {
        // Only queue notifications if the notification time is in the future
        final notificationDuration = savedEvent.notificationPreference.type == EventNotificationType.fiveMinutes
            ? const Duration(minutes: 5)
            : savedEvent.notificationPreference.type == EventNotificationType.fifteenMinutes
                ? const Duration(minutes: 15)
                : savedEvent.notificationPreference.type == EventNotificationType.thirtyMinutes
                    ? const Duration(minutes: 30)
                    : savedEvent.notificationPreference.type == EventNotificationType.oneHour
                        ? const Duration(hours: 1)
                        : savedEvent.notificationPreference.type == EventNotificationType.oneDay
                            ? const Duration(days: 1)
                            : savedEvent.notificationPreference.customDuration ?? const Duration(minutes: 30);
        
        final notificationTime = savedEvent.startDateTime.subtract(notificationDuration);
        
        // Only queue if the notification time hasn't passed yet
        if (notificationTime.isAfter(DateTime.now())) {
          await _eventNotificationQueueService.queueEventNotifications(savedEvent);
        }
      } catch (e) {
        debugPrint('EventEditorModal: Failed to queue notifications - $e');
      }

      setState(() {
        _currentEvent = savedEvent;
        _hasUnsavedChanges = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event saved')),
        );

        // Pop the modal with result
        Navigator.of(context).pop(
          EventEditorResult(
            savedEvent: savedEvent,
            draftEvent: savedEvent,
            wasSaved: true,
          ),
        );
        
        // Navigate to events screen, removing all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const EventsScreen(),
          ),
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _pickCoverImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // TODO: Upload image to Firebase Storage and get URL
      // For now, show a message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image upload not yet implemented')),
        );
      }
    }
  }

  Event _synchronizeCurrentEventFromControllers() {
    final String titleText = _titleController.text;
    final String descriptionText = _descriptionController.text;
    final String coverText = _coverImageUrlController.text.trim();
    final String capacityText = _capacityController.text.trim();
    final int? capacityValue =
        capacityText.isEmpty ? null : int.tryParse(capacityText);

    _currentEvent = _currentEvent.copyWith(
      title: titleText,
      description: descriptionText,
      coverImageUrl: coverText.isEmpty ? null : coverText,
      capacity: capacityValue,
    );
    return _currentEvent;
  }

  void _popWithDraftResult({
    bool wasSaved = false,
    Event? savedEvent,
    Event? draftOverride,
  }) {
    if (!mounted) return;
    final Event draftEvent =
        draftOverride ?? _synchronizeCurrentEventFromControllers();
    Navigator.of(context).pop(
      EventEditorResult(
        savedEvent: wasSaved ? (savedEvent ?? draftEvent) : savedEvent,
        draftEvent: draftEvent,
        wasSaved: wasSaved,
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    if (urlString.isEmpty ||
        urlString == 'about:blank' ||
        urlString == 'https://about:blank') {
      return;
    }

    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      launchableUrl = 'https://$launchableUrl';
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $launchableUrl');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $urlString')),
        );
      }
    }
  }

  Future<void> _handleBackNavigation() async {
    _popWithDraftResult();
  }

  bool get _isTimeRangeValid =>
      !_currentEvent.endDateTime.isBefore(_currentEvent.startDateTime);

  @override
  Widget build(BuildContext context) {
    final Duration duration =
        _currentEvent.endDateTime.difference(_currentEvent.startDateTime);
    final String durationText = _formatDuration(duration);
    final bool isTimeRangeValid = _isTimeRangeValid;
    final Color eventColor = _getEventColor(_currentEvent);
    final bool isDarkColor = _isDarkColor(eventColor);
    final Color foregroundColor = isDarkColor ? Colors.white : Colors.black;

    return WillPopScope(
      onWillPop: () async {
        _popWithDraftResult();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: eventColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackNavigation,
          ),
          title: TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foregroundColor,
            ),
            decoration: InputDecoration(
              hintText: 'Untitled Event',
              hintStyle: TextStyle(
                color: foregroundColor.withOpacity(0.6),
              ),
              border: InputBorder.none,
            ),
          ),
          actions: [
            if (_isSaving)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isTimeRangeValid
                        ? (isDarkColor 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.black.withOpacity(0.1))
                        : foregroundColor.withOpacity(0.3),
                    foregroundColor: foregroundColor,
                    elevation: 0,
                    padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: foregroundColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                  ),
                  onPressed: isTimeRangeValid ? _saveEvent : null,
                  child: const Text('Save'),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero / Cover Image
              _buildCoverImageSection(),

              // Schedule Section
              _buildScheduleSection(durationText),

              const Divider(height: 1),

              // Itinerary Section
              _buildItinerarySection(),

              const Divider(height: 1),

              // People Section
              _buildPeopleSection(),

              const Divider(height: 1),

              // Visibility & Sharing
              _buildVisibilitySection(),

              const Divider(height: 1),

              // Capacity & RSVPs
              _buildCapacitySection(),

              const Divider(height: 1),

              // Notifications
              _buildNotificationsSection(),

              const Divider(height: 1),

              // Description
              _buildDescriptionSection(),

              const Divider(height: 1),

              // Comments
              _buildCommentsSection(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImageSection() {
    final String? imageUrl = _coverImageUrlController.text.trim().isEmpty
        ? null
        : _coverImageUrlController.text.trim();

    return GestureDetector(
      onTap: () => _showCoverImageOptions(),
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Stack(
          children: [
            if (imageUrl == null)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Tap to add cover image',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            Positioned(
              bottom: 8,
              right: 8,
              child: FloatingActionButton.small(
                onPressed: _showCoverImageOptions,
                backgroundColor: Colors.white,
                child: const Icon(Icons.edit, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCoverImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final hasItineraryExperiences = _currentEvent.experiences.isNotEmpty;
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.collections_bookmark),
                title: const Text('Choose from experiences'),
                subtitle: hasItineraryExperiences
                    ? null
                    : const Text('Add itinerary experiences to enable'),
                enabled: hasItineraryExperiences,
                onTap: hasItineraryExperiences
                    ? () {
                        Navigator.of(ctx).pop();
                        _showExperienceCoverImageSelector();
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Enter image URL'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showImageUrlDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from device'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickCoverImage();
                },
              ),
              if (_coverImageUrlController.text.trim().isNotEmpty)
                ListTile(
                  leading: Icon(Icons.delete, color: theme.primaryColor),
                  title: Text('Remove image',
                      style: TextStyle(color: theme.primaryColor)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _coverImageUrlController.clear();
                      _markUnsavedChanges();
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showImageUrlDialog() {
    final controller =
        TextEditingController(text: _coverImageUrlController.text);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Cover Image URL'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://example.com/image.jpg',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _coverImageUrlController.text = controller.text.trim();
                  _markUnsavedChanges();
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String? _buildCoverImageUrlFromExperience(Experience experience) {
    final resourceName = experience.location.photoResourceName;
    if (resourceName != null && resourceName.isNotEmpty) {
      return GoogleMapsService.buildPlacePhotoUrlFromResourceName(
        resourceName,
        maxWidthPx: 800,
        maxHeightPx: 600,
      );
    }
    final photoUrl = experience.location.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return photoUrl;
    }
    return null;
  }

  /// Automatically updates the cover image from the top-most experience if:
  /// - Event has no cover image
  /// - Top-most experience changed
  void _updateCoverImageFromTopExperienceIfNeeded(
    String? previousTopExperienceId,
    List<EventExperienceEntry> updatedEntries,
  ) {
    // Check if event has no cover image
    final bool hasNoCoverImage = _coverImageUrlController.text.trim().isEmpty;
    if (!hasNoCoverImage) return;

    // Check if top-most experience changed
    final EventExperienceEntry? newTopEntry = updatedEntries.isNotEmpty
        ? updatedEntries.first
        : null;
    final String? newTopExperienceId = newTopEntry?.experienceId;
    final bool topExperienceChanged = previousTopExperienceId != newTopExperienceId;
    if (!topExperienceChanged) return;

    // Find the first experience with a valid cover image
    String? coverImageUrl;
    for (final entry in updatedEntries) {
      if (entry.isEventOnly) {
        // Event-only experiences: try to get image from inline location
        final photoResourceName = entry.inlineLocation?.photoResourceName;
        final photoUrl = entry.inlineLocation?.photoUrl;
        if (photoResourceName != null && photoResourceName.isNotEmpty) {
          coverImageUrl = GoogleMapsService.buildPlacePhotoUrlFromResourceName(
            photoResourceName,
            maxWidthPx: 800,
            maxHeightPx: 600,
          );
          break;
        } else if (photoUrl != null && photoUrl.isNotEmpty) {
          coverImageUrl = photoUrl;
          break;
        }
        // If no photo, continue to next experience
        continue;
      }

      // Saved experience: get from _availableExperiences
      final experience = _availableExperiences.firstWhereOrNull(
        (exp) => exp.id == entry.experienceId,
      );
      if (experience != null) {
        coverImageUrl = _buildCoverImageUrlFromExperience(experience);
        if (coverImageUrl != null) {
          break;
        }
      }
    }

    if (coverImageUrl != null) {
      _coverImageUrlController.text = coverImageUrl;
    }
  }

  void _showExperienceCoverImageSelector() {
    if (_currentEvent.experiences.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final mutedTextColor =
            theme.textTheme.bodySmall?.color?.withOpacity(0.7) ??
                Colors.grey[600];
        final primaryColor = theme.primaryColor;
        final itineraryExperiences = _currentEvent.experiences
            .map((entry) {
              if (entry.isEventOnly) {
                return MapEntry(entry, null);
              }
              return MapEntry(
                entry,
                _availableExperiences
                    .firstWhereOrNull((exp) => exp.id == entry.experienceId),
              );
            })
            .toList();

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Choose from experiences',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use a location photo from your itinerary.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (itineraryExperiences.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        'No experiences available yet. Add one to your itinerary first.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: mutedTextColor,
                        ),
                      ),
                    )
                  else
                    ...List.generate(itineraryExperiences.length, (index) {
                      final entry = itineraryExperiences[index].key;
                      final experience = itineraryExperiences[index].value;
                      
                      final bool isEventOnly = entry.isEventOnly;
                      final String displayName = isEventOnly
                          ? (entry.inlineName ?? 'Untitled')
                          : (experience?.name ?? 'Unknown experience');
                      
                      String? derivedUrl;
                      if (isEventOnly) {
                        final photoResourceName = entry.inlineLocation?.photoResourceName;
                        final photoUrl = entry.inlineLocation?.photoUrl;
                        if (photoResourceName != null && photoResourceName.isNotEmpty) {
                          derivedUrl = GoogleMapsService.buildPlacePhotoUrlFromResourceName(
                            photoResourceName,
                            maxWidthPx: 800,
                            maxHeightPx: 600,
                          );
                        } else if (photoUrl != null && photoUrl.isNotEmpty) {
                          derivedUrl = photoUrl;
                        }
                      } else if (experience != null) {
                        derivedUrl = _buildCoverImageUrlFromExperience(experience);
                      }
                      
                      final hasDerivedImage = derivedUrl != null;
                      final subtitle = isEventOnly
                          ? entry.inlineLocation?.getPlaceName()
                          : experience?.location.getPlaceName();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: primaryColor.withOpacity(0.1),
                          foregroundColor: primaryColor,
                          child: Text('${index + 1}'),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(displayName)),
                            if (isEventOnly)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade600,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Event-only',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: subtitle != null ? Text(subtitle) : null,
                        trailing: hasDerivedImage
                            ? const Icon(Icons.image, color: Colors.black54)
                            : const Text('No image',
                                style: TextStyle(color: Colors.grey)),
                        onTap: () {
                          if (!hasDerivedImage) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No image available yet for $displayName.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                          if (!mounted) return;
                          setState(() {
                            _coverImageUrlController.text = derivedUrl!;
                            _markUnsavedChanges();
                          });
                        },
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openItinerarySelector() async {
    if (widget.returnToSelectorOnItineraryTap) {
      _popWithDraftResult();
      return;
    }

    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to edit the itinerary.'),
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      final ownedExperiences =
          await _experienceService.getExperiencesByUser(userId, limit: 0);
      final sharedResult = await _experienceService.getExperiencesSharedWith(
        userId,
        limit: 300,
      );
      final sharedExperiences = sharedResult.$1;

      final Map<String, Experience> experienceMap = {
        for (final exp in _availableExperiences) exp.id: exp,
      };
      for (final exp in ownedExperiences) {
        experienceMap[exp.id] = exp;
      }
      for (final exp in sharedExperiences) {
        experienceMap[exp.id] = exp;
      }

      final selectedIds =
          _currentEvent.experiences.map((e) => e.experienceId).toList();

      final List<Experience> combinedExperiences = [];
      for (final id in selectedIds) {
        final exp = experienceMap.remove(id);
        if (exp != null) {
          combinedExperiences.add(exp);
        }
      }
      combinedExperiences.addAll(experienceMap.values);

      if (dialogContext != null) {
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      }
      if (!mounted) return;

      // Synchronize controller values before passing event to selector
      final eventForSelector = _synchronizeCurrentEventFromControllers();
      
      final selectedOrder = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (ctx) => EventExperienceSelectorScreen(
            categories: widget.categories,
            colorCategories: widget.colorCategories,
            experiences: combinedExperiences,
            preSelectedExperienceIds: selectedIds.toSet(),
            title: 'Edit Itinerary',
            returnSelectionOnly: true,
            initialEvent: eventForSelector,
          ),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      setState(() {
        _availableExperiences = combinedExperiences;
      });

      if (selectedOrder == null) {
        return;
      }

      final updatedEntries = _rebuildEntriesFromSelection(selectedOrder);
      
      // Track the previous top-most experience ID
      final String? previousTopExperienceId = _currentEvent.experiences.isNotEmpty
          ? _currentEvent.experiences.first.experienceId
          : null;
      
      setState(() {
        var updatedEvent =
            _currentEvent.copyWith(experiences: updatedEntries);
        updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
        _currentEvent = updatedEvent;
        
        // Automatically update cover image from top-most experience if needed
        _updateCoverImageFromTopExperienceIfNeeded(
          previousTopExperienceId,
          updatedEvent.experiences,
        );
        
        _markUnsavedChanges();
      });
    } catch (e) {
      if (dialogContext != null) {
        Navigator.of(dialogContext!).pop();
        dialogContext = null;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open itinerary: $e')),
        );
      }
    }
  }

  Future<void> _createEventOnlyExperience() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    Location? selectedLocation;
    String? selectedIcon;
    String? selectedColorCategoryId;
    String? customColorHex;

    final result = await showDialog<EventExperienceEntry>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final ColorCategory? selectedColorCategory = widget.colorCategories.firstWhereOrNull(
              (color) => color.id == selectedColorCategoryId,
            );
            
            // Determine the display color (from category or custom)
            Color? displayColor;
            if (selectedColorCategory != null) {
              displayColor = selectedColorCategory.color;
            } else if (customColorHex != null && customColorHex!.isNotEmpty) {
              displayColor = _parseColor(customColorHex!);
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Add Event-Only Experience'),
                  const SizedBox(height: 4),
                  Text(
                    'For this event only. This will not be saved in your collection of categories and experiences.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
              content: GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping outside text fields
                  FocusScope.of(context).unfocus();
                },
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name field
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name *',
                            hintText: 'e.g., Lunch at Central Park',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Description field
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional details',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      // Location selection
                      OutlinedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: Text(selectedLocation != null
                            ? selectedLocation!.getPlaceName()
                            : 'Select Location (Optional)'),
                        onPressed: () async {
                          final location = await _pickLocation();
                          if (location != null) {
                            setDialogState(() {
                              selectedLocation = location;
                            });
                          }
                        },
                      ),
                      if (selectedLocation != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          selectedLocation!.address ?? 'Location selected',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Icon selection
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.category,
                          color: selectedIcon != null
                              ? Theme.of(context).primaryColor
                              : null,
                        ),
                        label: Text(selectedIcon != null
                            ? selectedIcon!
                            : 'Select Icon (Optional)'),
                        onPressed: () async {
                          final icon = await _pickCategory();
                          if (icon != null) {
                            setDialogState(() {
                              selectedIcon = icon;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Color category selection
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.palette,
                          color: displayColor,
                        ),
                        label: Text(selectedColorCategory != null
                            ? selectedColorCategory.name
                            : customColorHex != null
                                ? 'Custom Color'
                                : 'Select Color (Optional)'),
                        onPressed: () async {
                          final colorResult = await _pickColorCategory(
                            initialColorCategoryId: selectedColorCategoryId ?? 
                                (customColorHex != null ? 'custom:$customColorHex' : null),
                          );
                          if (colorResult != null) {
                            setDialogState(() {
                              if (colorResult.startsWith('custom:')) {
                                // Custom color selected
                                selectedColorCategoryId = null;
                                customColorHex = colorResult.substring(7); // Remove "custom:" prefix
                              } else {
                                // Category selected
                                selectedColorCategoryId = colorResult;
                                customColorHex = null;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Notes field
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Add notes and details about this stop!',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes),
                        ),
                        minLines: 3,
                        maxLines: null,
                      ),
                    ],
                  ),
                ),
              ),
                ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name is required')),
                      );
                      return;
                    }

                    final entry = EventExperienceEntry(
                      experienceId: '', // Empty for event-only
                      inlineName: name,
                      inlineDescription: descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      inlineLocation: selectedLocation,
                      inlineCategoryId: null, // No category ID for event-only
                      inlineColorCategoryId: selectedColorCategoryId,
                      inlineCategoryIconDenorm: selectedIcon,
                      inlineColorHexDenorm: selectedColorCategory != null
                          ? '#${selectedColorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}'
                          : null,
                      note: notesController.text.trim().isEmpty
                          ? null
                          : notesController.text.trim(),
                    );

                    Navigator.of(ctx).pop(entry);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        // Track the previous top-most experience ID
        final String? previousTopExperienceId = _currentEvent.experiences.isNotEmpty
            ? _currentEvent.experiences.first.experienceId
            : null;

        final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
        entries.add(result);
        var updatedEvent = _currentEvent.copyWith(experiences: entries);
        updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
        _currentEvent = updatedEvent;

        // Automatically update cover image from top-most experience if needed
        _updateCoverImageFromTopExperienceIfNeeded(
          previousTopExperienceId,
          updatedEvent.experiences,
        );

        _markUnsavedChanges();
      });
    }
  }

  Future<void> _editEventOnlyExperience(EventExperienceEntry entry, int index) async {
    final TextEditingController nameController = TextEditingController(
      text: entry.inlineName ?? '',
    );
    final TextEditingController notesController = TextEditingController(
      text: entry.note ?? '',
    );
    Location? selectedLocation = entry.inlineLocation;
    String? selectedIcon = entry.inlineCategoryIconDenorm;
    String? selectedColorCategoryId = entry.inlineColorCategoryId;
    String? customColorHex = entry.inlineColorHexDenorm;

    final result = await showDialog<EventExperienceEntry>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final ColorCategory? selectedColorCategory = widget.colorCategories.firstWhereOrNull(
              (color) => color.id == selectedColorCategoryId,
            );
            
            // Determine the display color (from category or custom)
            Color? displayColor;
            if (selectedColorCategory != null) {
              displayColor = selectedColorCategory.color;
            } else if (customColorHex != null && customColorHex!.isNotEmpty) {
              displayColor = _parseColor(customColorHex!);
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Edit Event-Only Experience'),
                  const SizedBox(height: 4),
                  Text(
                    'For this event only. This will not be saved in your collection of categories and experiences.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
              content: GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping outside text fields
                  FocusScope.of(context).unfocus();
                },
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name field
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name *',
                            hintText: 'e.g., Lunch at Central Park',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Notes field
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Add notes and details about this stop!',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes),
                        ),
                        minLines: 3,
                        maxLines: null,
                      ),
                      const SizedBox(height: 16),
                      // Location selection
                      OutlinedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: Text(selectedLocation != null
                            ? selectedLocation!.getPlaceName()
                            : 'Select Location (Optional)'),
                        onPressed: () async {
                          final location = await _pickLocation();
                          if (location != null) {
                            setDialogState(() {
                              selectedLocation = location;
                            });
                          }
                        },
                      ),
                      if (selectedLocation != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          selectedLocation!.address ?? 'Location selected',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Icon selection
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.category,
                          color: selectedIcon != null
                              ? Theme.of(context).primaryColor
                              : null,
                        ),
                        label: Text(selectedIcon != null
                            ? selectedIcon!
                            : 'Select Icon (Optional)'),
                        onPressed: () async {
                          final icon = await _pickCategory(initialIcon: selectedIcon);
                          if (icon != null) {
                            setDialogState(() {
                              selectedIcon = icon;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Color category selection
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.palette,
                          color: displayColor,
                        ),
                        label: Text(selectedColorCategory != null
                            ? selectedColorCategory.name
                            : customColorHex != null
                                ? 'Custom Color'
                                : 'Select Color (Optional)'),
                        onPressed: () async {
                          final colorResult = await _pickColorCategory(
                            initialColorCategoryId: selectedColorCategoryId ?? 
                                (customColorHex != null ? 'custom:$customColorHex' : null),
                          );
                          if (colorResult != null) {
                            setDialogState(() {
                              if (colorResult.startsWith('custom:')) {
                                // Custom color selected
                                selectedColorCategoryId = null;
                                customColorHex = colorResult.substring(7); // Remove "custom:" prefix
                              } else {
                                // Category selected
                                selectedColorCategoryId = colorResult;
                                customColorHex = null;
                              }
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
                ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name is required')),
                      );
                      return;
                    }

                    final updatedEntry = entry.copyWith(
                      inlineName: name,
                      inlineDescription: null, // Description field removed
                      inlineLocation: selectedLocation,
                      inlineCategoryId: null, // No category ID for event-only
                      inlineColorCategoryId: selectedColorCategoryId,
                      inlineCategoryIconDenorm: selectedIcon,
                      inlineColorHexDenorm: selectedColorCategory != null
                          ? '#${selectedColorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}'
                          : customColorHex,
                      note: notesController.text.trim().isEmpty
                          ? null
                          : notesController.text.trim(),
                    );

                    Navigator.of(ctx).pop(updatedEntry);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
        entries[index] = result;
        _currentEvent = _currentEvent.copyWith(experiences: entries);
        _markUnsavedChanges();
      });
    }
  }

  Future<Location?> _pickLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: null,
          onLocationSelected: (location) {},
        ),
      ),
    );

    if (result != null && mounted) {
      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;

      try {
        if (selectedLocation.placeId == null ||
            selectedLocation.placeId!.isEmpty) {
          return selectedLocation;
        }

        // Fetch detailed location information
        final detailedLocation = await GoogleMapsService()
            .getPlaceDetails(selectedLocation.placeId!);
        return detailedLocation;
      } catch (e) {
        print('Error getting place details for event-only location: $e');
        return selectedLocation;
      }
    }

    return null;
  }

  Future<String?> _pickCategory({String? initialIcon}) async {
    // Expanded list of emojis for selection (same as add_category_modal.dart)
    final List<String> emojiOptions = [
      // Food & Drink
      '🍎', '🍏', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', '🥭',
      '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🫛', '🥒', '🌶️', '🌽', '🥕', '🫑', '🥔', '🧅', '🧄', '🍄', '🥜',
      '🌰', '🍞', '🥐', '🥯', '🥞', '🍳', '🧇', '🥓', '🥩', '🍗', '🍖', '🍤', '🍣', '🍱', '🍚', '🍛', '🍜',
      '🍲', '🥣', '🥗', '🍝', '🍠', '🥡', '🥪', '🌭', '🍔', '🍟', '🍕', '🥫', '🥙', '🥘', '🌮', '🌯', '🥨', '🥟',
      '🦪', '🦞', '🦐', '🦑', '🍢', '🍡', '🍧', '🍨', '🍦', '🥧', '🍰', '🎂', '🧁', '🍮', '🍭', '🍬', '🍫', '🍿', '🍩', '🍪',
      '🍯', '🥤', '🧃', '🧉', '🧊', '🥛', '☕', '🫖', '🧋', '🍵', '🍶', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻', '🥂', '🥃',
      
      // Utensils & Tableware
      '🍽️', '🥢', '🍴', '🥄', '🧂',

      // Places & Buildings
      '🏠', '🏡', '🏢', '🏣', '🏤', '🏥', '🏦', '🏨', '🏩', '🏪', '🏫', '🏬', '🏭', '🏯', '🏰', '🏛️', '⛪', '🕌', '🕍',
      '⛩️', '🕋', '⛲', '🗽', '🗼', '🏟️', '🎡', '🎢', '🎠', '⛺', '🏕️', '🏖️', '🏜️', '🏝️', '🏞️', '⛰️', '🏔️', '🗻', '🌋', '🏗️', '🛖',
      '🛣️', '🛤️', '🗺️', '🧭', '📍', '🏘️', '🌳', '🌆', '🌇', '🌅', '🌄', '⛱️', '🛍️', '🛒', '💈', '♨️', '⭐', '🌠', '🌌', '🪐', '🌍', '🌏', '🌎', '🪨', '🪵',
      '❄️', '☃️',

      // Nature & Plants
      '🌵', '🌲', '🌳', '🌴', '🌱', '🌿', '☘️', '🍀', '🎍', '🎋', '🍂', '🍁', '🍃', '🪴', '🏵️', '🌸', '🌹', '🌺', '🌻', '🌼', '🌷', '💐', '🥀',

      // Animals
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒',
      '🦍', '🦧', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🐝', '🪲', '🐛', '🐞', '🦋', '🐌', '🐜', '🐢', '🐍', '🦎', '🦂', '🦗', '🕷️', '🕸️', '🦟', '🐠', '🐟', '🐡', '🦈', '🐬', '🐳', '🐋', '🦭', '🦦', '🦑', '🦐', '🦞', '🦀', '🪼', '🐙', '🐊', '🐅', '🐆', '🦓', '🦒', '🐘', '🦏', '🦛', '🐪', '🐫', '🦙', '🦘', '🐃', '🐂', '🐄', '🐎', '🐖', '🐏', '🐑', '🦢', '🦩', '🦚', '🦜', '🦃', '🐓', '🦤', '🦥', '🦦', '🦨', '🦧', '🦣', '🦫', '🐇', '🦝', '🦡', '🦥', '🦬', '🦦', '🦨', '🦩', '🐉', '🐲', '🪽', '🕊️', '🐦‍⬛', '🐤', '🦢',

      // Faces & People
      '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '🥹', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🫢', '🫣', '🤫', '🤔', '🫠', '🤐', '🤨', '😐', '😑', '😶', '😶‍🌫️', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '😵‍💫', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '🫤', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👨‍🦰', '👨‍🦱', '👨‍🦳', '👨‍🦲', '👩', '👩‍🦰', '👩‍🦱', '👩‍🦳', '👩‍🦲', '👱‍♀️', '👱‍♂️', '🧓', '👴', '👵', '🙍‍♂️', '🙍‍♀️', '🙎‍♂️', '🙎‍♀️', '🙅‍♂️', '🙅‍♀️', '🙆‍♂️', '🙆‍♀️', '💁‍♀️', '💁‍♂️', '🙋‍♀️', '🙋‍♂️', '🧏‍♂️', '🧏‍♀️', '🙇‍♂️', '🙇‍♀️', '🤦‍♂️', '🤦‍♀️', '🤷‍♂️', '🤷‍♀️', '🧑‍⚕️', '🧑‍🎓', '🧑‍🏫', '🧑‍⚖️', '🧑‍🌾', '🧑‍🍳', '🧑‍🔧', '🧑‍🏭', '🧑‍💼', '🧑‍🔬', '🧑‍💻', '🧑‍🎤', '🧑‍🎨', '🧑‍✈️', '🧑‍🚀', '🧑‍🚒', '👮‍♀️', '👮‍♂️', '🕵️‍♀️', '🕵️‍♂️', '💂‍♀️', '💂‍♂️', '🥷', '👷‍♀️', '👷‍♂️', '🤴', '👸', '👳‍♂️', '👳‍♀️', '👲', '🧕', '🤵', '👰', '🤰', '🤱', '🫄', '🫃', '🧑‍🍼', '👼', '🎅', '🤶', '🧑‍🎄', '🦸‍♂️', '🦸‍♀️', '🦹‍♂️', '🦹‍♀️', '🧙‍♂️', '🧙‍♀️', '🧚‍♂️', '🧚‍♀️', '🧛‍♂️', '🧛‍♀️', '🧜‍♂️', '🧜‍♀️', '🧝‍♂️', '🧝‍♀️', '🧞‍♂️', '🧞‍♀️', '🧟‍♂️', '🧟‍♀️', '🧌', '🚶‍♂️', '🚶‍♀️', '🧍‍♂️', '🧍‍♀️', '🧎‍♂️', '🧎‍♀️', '🧑‍🦯', '🧑‍🦼', '🧑‍🦽', '🏃‍♂️', '🏃‍♀️', '💃', '🕺', '🧗', '🧗‍♂️', '🧗‍♀️', '🏇', '🏂', '🏌️‍♀️', '🏌️‍♂️', '🏄‍♂️', '🏄‍♀️', '🏊‍♂️', '🏊‍♀️', '🚣‍♂️', '🚣‍♀️',

      // Hand Gestures
      '☝️', '👆', '👇', '👈', '👉', '🖖', '✋', '🤚', '🖐️', '🖑', '🤙', '🫱', '🫲', '🫳', '🫴', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🫶', '🙌', '👐', '🤲', '🙏', '🫂', '✍️',
      
      // Objects & Everyday Items
      '💄', '💋', '💍', '💎', '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🧮', '🎥', '📷', '📹', '📼',
      '☎️', '📞', '📟', '📠', '📺', '📻', '⏰', '⏱️', '⏲️', '🕰️', '🔋', '🔌', '💡', '🔦', '🕯️', '🧯', '🛢️', '🛒', '💳', '💰', '💵', '💴', '💶', '💷', '💸', '🧾', '💼', '📁', '📂', '🗂️', '📅', '📆', '🗒️', '🗓️', '📇', '📈', '📉', '📊', '📋', '📌', '📎', '🖇️', '📏', '📐', '✂️', '🗃️', '🗄️', '🗑️', '🔒', '🔓', '🔏', '🔐', '🔑', '🗝️', '🔨', '🪓', '⛏️', '⚒️', '🛠️', '🗡️', '⚔️', '🔫', '🪃', '🏹', '🛡️', '🔧', '🪛', '🔩', '⚙️', '🛞', '🧱', '⛓️', '🧲', '🪜', '⚗️', '🧪', '🧫', '🧬', '🔬', '🔭', '📡', '💉', '🩸', '💊', '🩹', '🩺',

      // Clothing & Accessories
      '👓', '🕶️', '🥽', '🥼', '🦺', '👔', '👕', '👖', '🧣', '🧤', '🧥', '🧦', '👗', '👘', '🥻', '🩱', '🩲', '🩳', '👙', '👚', '👛', '👜', '👝', '🛍️', '🎒', '🩴', '👞', '👟', '🥾', '🥿', '👠', '👡', '🩰', '👢', '👑', '👒', '🎩', '🎓', '🧢', '🪖', '⛑️', '💄', '💍', '💼', 
      
      // Music & Arts
      '🎤', '🎧', '🎼', '🎵', '🎶', '🎷', '🎸', '🎹', '🥁', '🎺', '🎻', '🎬', '🎨', '🎭',
      
      // Celebration & Party
      '🎂', '🎉', '🎊', '🎈', '🎇', '🎆', '✨', '🪄', '🎎', '🎏', '🪅', '🪩', '🎀', '🎁', '🪧', '🧧', '🎐', 
      
      // Sports & Activities
      '⚽', '⚾', '🏀', '🏐', '🏈', '🏉', '🎱', '🎳', '🥎', '🏓', '🏸', '🏒', '🏑', '🏏', '🥅', '🥊', '🥋', '🥌', '⛳', '⛸️', '🎣', '🎽', '🎿', '🛷', '⛷️', '🏂', '🪂', '🏹', '🧗', '🧗‍♂️', '🧗‍♀️', '🚵', '🚵‍♂️', '🚵‍♀️', '🚴', '🚴‍♂️', '🚴‍♀️', '🏊', '🏊‍♂️', '🏊‍♀️', '🤽', '🤽‍♂️', '🤽‍♀️', '🏄', '🏄‍♂️', '🏄‍♀️', '🧘', '🏋️', '🏋️‍♂️', '🏋️‍♀️', '🤸', '🤸‍♂️', '🤸‍♀️', '⛹️', '⛹️‍♂️', '⛹️‍♀️', '🤼', '🤼‍♂️', '🤼‍♀️', '🤾', '🤾‍♂️', '🤾‍♀️', '🧙‍♂️', '🧙‍♀️', '🎮', '🕹️', '🎲', '🧩', '🧸', '🪁', '🪀', '🎰', '🎯', '🪃', '🛹', '🛼', '🥏', '🪃', '🎠', '🎡', '🥍', 
      
      // Awards & Achievement
      '🏆', '🏅', '🥇', '🥈', '🥉', '🎫', '🎟️',
      
      // Science, Education & Office
      '📖', '📚', '📓', '📒', '📔', '📕', '📗', '📘', '📙', '📚', '🧮', '🔬', '🔭', '🛰️', '🔬', '📡', '🧪', '🧫', '🧬', '📝', '✏️', '✒️', '🖋️', '🖊️', '🖌️', '🖍️', '📅', '📆', '🗓️', '📇', '📈', '📉', '📊', '📋', '📌', '📎', '🖇️', 
      
      // Transportation & Travel
      '🚗', '🚕', '🚙', '🛻', '🚐', '🚚', '🚛', '🚜', '🦽', '🦼', '🛴', '🚲', '🛵', '🏍️', '🛺', '🚔', '🚓', '🚑', '🚒', '🚐', '🚚', '🚛', '🛻', '🚜', '🛴', '🛹', '🛼', '🚂', '🚃', '🚄', '🚅', '🚆', '🚇', '🚈', '🚉', '🚊', '🚝', '🚞', '🚋', '🚌', '🚍', '🚎', '🚐', '🏎️', '🚓', '⛵', '🛥️', '🚤', '🛳️', '⛴️', '🚢', '✈️', '🛩️', '🛫', '🛬', '🪂', '💺', '🚁', '🛰️', '🚀', '🛸', '🪐',
      
      // Shapes, Symbols, & Miscellaneous
      '❤️', '🩷', '🧡', '💛', '💚', '💙', '🩵', '💜', '🤎', '🖤', '🤍', '🩶', '💔', '❤️‍🔥', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '🔘', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '🟤', '⚫', '⚪', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪', '🟫', '⬛', '⬜', '◼️', '◻️', '◾', '◽', '▪️', '▫️', '◯', '❓', '❔', '❗', '‼️', '⁉️', '✔️', '☑️', '✅', '❌', '✖️', '➕', '➖', '➗', '✳️', '✴️', '➰', '➿', '〽️', '💲', '💯', '♠️', '♥️', '♦️', '♣️', '🃏', '🀄', '🎴', '🔔', '🔕', '🔒', '🔓', '🔏', '🔐', '🔑', '🗝️', '⚓', '🚬', '🪦', '⚖️', '♀️', '♂️', '⚧️',
      
      // Weather
      '☀️', '🌤️', '⛅', '⛈️', '🌩️', '🌧️', '🌨️', '❄️', '☁️', '🌦️', '🌪️', '🌫️', '🌬️', '🌈', '☃️', '🌂', '☔', '💧', '💦', '🫧',
      
      // Flags
      '🇦🇫','🇦🇱','🇩🇿','🇦🇩','🇦🇴','🇦🇬','🇦🇷','🇦🇲','🇦🇺','🇦🇹','🇦🇿','🇧🇸','🇧🇭','🇧🇩','🇧🇧','🇧🇾','🇧🇪','🇧🇿','🇧🇯','🇧🇹','🇧🇴','🇧🇦','🇧🇼','🇧🇷','🇧🇳','🇧🇬','🇧🇫','🇧🇮','🇨🇻','🇰🇭','🇨🇲','🇨🇦','🇨🇫','🇹🇩','🇨🇱','🇨🇳','🇨🇴','🇰🇲','🇨🇬','🇨🇩','🇨🇷','🇭🇷','🇨🇺','🇨🇾','🇨🇿','🇩🇰','🇩🇯','🇩🇲','🇩🇴','🇪🇨','🇪🇬','🇸🇻','🇬🇶','🇪🇷','🇪🇪','🇪🇸','🇪🇹','🇫🇲','🇫🇮','🇫🇷','🇬🇦','🇬🇲','🇬🇪','🇩🇪','🇬🇭','🇬🇷','🇬🇩','🇬🇹','🇬🇳','🇬🇼','🇬🇾','🇭🇹','🇭🇳','🇭🇺','🇮🇸','🇮🇳','🇮🇩','🇮🇷','🇮🇶','🇮🇪','🇮🇱','🇮🇹','🇯🇲','🇯🇵','🇯🇴','🇰🇿','🇰🇪','🇰🇮','🇰🇵','🇰🇷','🇽🇰','🇰🇼','🇰🇬','🇱🇦','🇱🇻','🇱🇧','🇱🇸','🇱🇷','🇱🇾','🇱🇮','🇱🇹','🇱🇺','🇲🇬','🇲🇼','🇲🇾','🇲🇻','🇲🇱','🇲🇹','🇲🇭','🇲🇷','🇲🇺','🇲🇽','🇲🇩','🇲🇨','🇲🇳','🇲🇪','🇲🇦','🇲🇿','🇲🇲','🇳🇦','🇳🇷','🇳🇵','🇳🇱','🇳🇿','🇳🇮','🇳🇪','🇳🇬','🇳🇴','🇴🇲','🇵🇰','🇵🇼','🇵🇸','🇵🇦','🇵🇬','🇵🇾','🇵🇪','🇵🇭','🇵🇱','🇵🇹','🇶🇦','🇷🇴','🇷🇺','🇷🇼','🇰🇳','🇱🇨','🇻🇨','🇼🇸','🇸🇲','🇸🇹','🇸🇦','🇸🇳','🇷🇸','🇸🇨','🇸🇱','🇸🇬','🇸🇰','🇸🇮','🇸🇧','🇸🇴','🇿🇦','🇸🇸','🇪🇸','🇱🇰','🇸🇩','🇸🇷','🇸🇪','🇨🇭','🇸🇾','🇹🇼','🇹🇯','🇹🇿','🇹🇭','🇹🇱','🇹🇬','🇹🇴','🇹🇹','🇹🇳','🇹🇷','🇹🇲','🇹🇻','🇺🇬','🇺🇦','🇦🇪','🇬🇧','🇺🇸','🇺🇾','🇺🇿','🇻🇺','🇻🇦','🇻🇪','🇻🇳','🇾🇪','🇿🇲','🇿🇼',
      '🏳️‍🌈','🏴‍☠️','🏳️','🏁','🚩','🏴','🏳️‍⚧️','🏳️‍🌈',
    ];

    String? selectedIcon = initialIcon;
    
    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Select Icon'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: emojiOptions.length,
                        itemBuilder: (context, index) {
                          final emoji = emojiOptions[index];
                          final isSelected = emoji == selectedIcon;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedIcon = emoji;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue.shade100
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(color: Colors.blue, width: 2)
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedIcon != null
                      ? () => Navigator.of(ctx).pop(selectedIcon)
                      : null,
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _pickCustomColor({Color? initialColor}) async {
    Color selectedColor = initialColor ?? Colors.blue;
    
    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Pick a color'),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    setDialogState(() {
                      selectedColor = color;
                    });
                  },
                  pickerAreaHeightPercent: 0.8,
                  enableAlpha: false, // Disable alpha channel
                  displayThumbColor: true,
                  paletteType: PaletteType.hsl,
                  pickerAreaBorderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2.0),
                    topRight: Radius.circular(2.0),
                  ),
                  hexInputBar: true,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                ElevatedButton(
                  child: const Text('Select'),
                  onPressed: () {
                    final hexColor = '#${selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                    Navigator.of(ctx).pop('custom:$hexColor');
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _pickColorCategory({String? initialColorCategoryId}) async {
    final List<ColorCategory> categoriesToShow = List.from(widget.colorCategories);
    
    // Check if initial selection is a custom color
    Color? initialCustomColor;
    if (initialColorCategoryId != null && initialColorCategoryId.startsWith('custom:')) {
      final hexString = initialColorCategoryId.substring(7); // Remove "custom:" prefix
      try {
        initialCustomColor = _parseColor(hexString);
      } catch (e) {
        // If parsing fails, ignore
      }
    }

    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Select Color Category',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: categoriesToShow.length,
                    itemBuilder: (context, index) {
                      final category = categoriesToShow[index];
                      final bool isSelected =
                          category.id == initialColorCategoryId;
                      return ListTile(
                        leading: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              color: category.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.grey.shade400, width: 1)),
                        ),
                        title: Text(category.name),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx, category.id);
                        },
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: initialCustomColor ?? Colors.grey.shade300,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.grey.shade400, width: 1)),
                        ),
                        title: Text('Custom Color',
                            style: TextStyle(
                                color: initialCustomColor != null
                                    ? Colors.blue[700]
                                    : Colors.grey[700])),
                        trailing: initialCustomColor != null
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () async {
                          // Show color picker as nested dialog
                          final customColorResult = await _pickCustomColor(
                            initialColor: initialCustomColor,
                          );
                          if (customColorResult != null) {
                            // Close the category dialog and return the custom color
                            Navigator.of(ctx).pop(customColorResult);
                          }
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.cancel_outlined,
                            size: 20, color: Colors.grey[700]),
                        label: Text('Cancel',
                            style: TextStyle(color: Colors.grey[700])),
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<EventExperienceEntry> _rebuildEntriesFromSelection(
      List<String> selectedIds) {
    final Map<String, EventExperienceEntry> existingEntries = {
      for (final entry in _currentEvent.experiences) entry.experienceId: entry,
    };
    
    // Track which existing saved experiences we've already included
    final Set<String> includedExistingIds = {};
    
    // Preserve original order: iterate through original entries and keep them in place
    // Event-only experiences always stay, saved experiences only if selected
    final List<EventExperienceEntry> result = [];
    for (final entry in _currentEvent.experiences) {
      if (entry.isEventOnly) {
        // Always preserve event-only experiences in their original position
        result.add(entry);
      } else if (selectedIds.contains(entry.experienceId)) {
        // Include saved experience if it's in the selection
        result.add(entry);
        includedExistingIds.add(entry.experienceId);
      }
      // If saved experience is not in selectedIds, skip it (removed from selection)
    }
    
    // Append new saved experiences (not in original list) at the end
    for (final id in selectedIds) {
      if (!includedExistingIds.contains(id)) {
        result.add(existingEntries[id] ?? EventExperienceEntry(experienceId: id));
      }
    }
    
    return result;
  }

  Widget _buildScheduleSection(String durationText) {
    // Get current event color (custom or default)
    final currentColor = _getEventColor(_currentEvent);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Tooltip(
                message: 'View event on map',
                child: ActionChip(
                  avatar: Image.asset(
                    'assets/icon/icon-cropped.png',
                    height: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: () => _openEventMapView(),
                  tooltip: 'View event on map',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _pickEventColor(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: currentColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.shade400,
                      width: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDateTimePicker(
            label: 'Start',
            dateTime: _currentEvent.startDateTime,
            onChanged: (newDateTime) {
              setState(() {
                var updatedEvent = _currentEvent.copyWith(
                  startDateTime: newDateTime,
                );
                updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
                _currentEvent = updatedEvent;
                _markUnsavedChanges();
              });
            },
          ),
          const SizedBox(height: 16),
          _buildDateTimePicker(
            label: 'End',
            dateTime: _currentEvent.endDateTime,
            onChanged: (newDateTime) {
              setState(() {
                _currentEvent = _currentEvent.copyWith(
                  endDateTime: newDateTime,
                );
                _markUnsavedChanges();
              });
            },
            minDateTime: _currentEvent.startDateTime,
          ),
          const SizedBox(height: 8),
          Text(
            'Duration: $durationText',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required DateTime dateTime,
    required ValueChanged<DateTime> onChanged,
    DateTime? minDateTime,
    DateTime? maxDateTime,
  }) {
    final DateTime effectiveMinDate = minDateTime ?? DateTime(2000);
    final DateTime effectiveMaxDate = maxDateTime ?? DateTime(2100);
    final DateTime initialDate = dateTime.isBefore(effectiveMinDate)
        ? effectiveMinDate
        : dateTime.isAfter(effectiveMaxDate)
            ? effectiveMaxDate
            : dateTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            Widget wrapPicker(Widget? child) =>
                _wrapPickerWithWhiteTheme(context, child);

            final date = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: effectiveMinDate,
              lastDate: effectiveMaxDate,
              builder: (ctx, child) => wrapPicker(child),
            );
            if (date == null || !mounted) return;

            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(initialDate),
              builder: (ctx, child) => wrapPicker(child),
            );
            if (time == null || !mounted) return;

            final newDateTime = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            if (minDateTime != null && newDateTime.isBefore(minDateTime)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label time must be after the start time.'),
                ),
              );
              return;
            }
            if (maxDateTime != null && newDateTime.isAfter(maxDateTime)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('$label time must be before the available range.'),
                ),
              );
              return;
            }
            onChanged(newDateTime);
          },
          child: Text(_formatDateTime(dateTime)),
        ),
      ],
    );
  }

  Widget _wrapPickerWithWhiteTheme(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    // Create a lighter version of primary color for unselected hour/minute
    final primaryColor = theme.colorScheme.primary;
    final lighterPrimary = Color.lerp(primaryColor, Colors.white, 0.7) ??
        primaryColor.withOpacity(0.3);

    return Theme(
      data: theme.copyWith(
        dialogBackgroundColor: Colors.white,
        colorScheme: theme.colorScheme.copyWith(
          surface: Colors.white,
          background: Colors.white,
          onSurface: Colors.black,
          primary: theme.colorScheme.primary,
          onPrimary: Colors.white,
        ),
        datePickerTheme: theme.datePickerTheme.copyWith(
          backgroundColor: Colors.white,
          headerBackgroundColor: Colors.white,
          headerForegroundColor: Colors.black,
          dayStyle: theme.datePickerTheme.dayStyle?.copyWith(
            color: Colors.black,
          ),
          weekdayStyle: theme.datePickerTheme.weekdayStyle?.copyWith(
            color: Colors.black87,
          ),
          yearStyle: theme.datePickerTheme.yearStyle?.copyWith(
            color: Colors.black,
          ),
        ),
        timePickerTheme: theme.timePickerTheme.copyWith(
          backgroundColor: Colors.white,
          hourMinuteColor: MaterialStateColor.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return theme.colorScheme.primary; // Selected: primary color
            }
            return lighterPrimary; // Unselected: lighter primary color
          }),
          hourMinuteTextColor: MaterialStateColor.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.white; // Selected: white text
            }
            return Colors.black87; // Unselected: dark text
          }),
          dialHandColor: theme.colorScheme.primary,
          dayPeriodColor: MaterialStateColor.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return theme.colorScheme.primary; // Selected: primary color
            }
            return lighterPrimary; // Unselected: lighter primary color (same as hour/minute)
          }),
          dayPeriodTextColor: MaterialStateColor.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.white; // Selected: white text
            }
            return Colors
                .black87; // Unselected: dark text (same as hour/minute)
          }),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Widget _buildItinerarySection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Itinerary (${_currentEvent.experiences.length} experiences)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add event-only experience',
                child: InkWell(
                  onTap: _createEventOnlyExperience,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade600,
                    ),
                    child: const Icon(Icons.edit_note, color: Colors.white, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add from saved experiences',
                child: InkWell(
                  onTap: _openItinerarySelector,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).primaryColor,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_currentEvent.experiences.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No experiences added yet.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _currentEvent.experiences.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  // Track the previous top-most experience ID
                  final String? previousTopExperienceId = _currentEvent.experiences.isNotEmpty
                      ? _currentEvent.experiences.first.experienceId
                      : null;
                  
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final entries = List<EventExperienceEntry>.from(
                      _currentEvent.experiences);
                  final entry = entries.removeAt(oldIndex);
                  entries.insert(newIndex, entry);
                  var updatedEvent =
                      _currentEvent.copyWith(experiences: entries);
                  updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
                  _currentEvent = updatedEvent;
                  
                  // Automatically update cover image from top-most experience if needed
                  _updateCoverImageFromTopExperienceIfNeeded(
                    previousTopExperienceId,
                    updatedEvent.experiences,
                  );
                  
                  _markUnsavedChanges();
                });
              },
              itemBuilder: (context, index) {
                final entry = _currentEvent.experiences[index];
                final Experience? experience = entry.isEventOnly
                    ? null
                    : _availableExperiences.firstWhereOrNull(
                        (exp) => exp.id == entry.experienceId,
                      );
                return _SlidingItineraryItem(
                  key: ValueKey(entry.isEventOnly 
                      ? 'event-only-${entry.inlineName ?? 'unnamed'}-$index'
                      : '${entry.experienceId}-$index'),
                  index: index,
                  child: _buildItineraryEntryCard(entry, experience, index),
                );
              },
            ),
          const SizedBox(height: 16),
          // Add Event-Only Experience button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _createEventOnlyExperience,
              icon: const Icon(Icons.edit_note, size: 18, color: Colors.white),
              label: const Text('Add Event-Only Experience', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Add Saved Experiences button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openItinerarySelector,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add from Saved Experiences'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItineraryEntryCard(
    EventExperienceEntry entry,
    Experience? experience,
    int index,
  ) {
    // Determine if this is an event-only experience
    final bool isEventOnly = entry.isEventOnly;
    
    // Get display values from either the saved experience or inline data
    final String displayName = isEventOnly
        ? (entry.inlineName ?? 'Untitled')
        : (experience?.name ?? 'Unknown Experience');
    
    final String? categoryId = isEventOnly
        ? entry.inlineCategoryId
        : experience?.categoryId;
    
    final String? colorCategoryId = isEventOnly
        ? entry.inlineColorCategoryId
        : experience?.colorCategoryId;
    
    final UserCategory? category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == categoryId,
    );
    final ColorCategory? colorCategory =
        widget.colorCategories.firstWhereOrNull(
      (color) => color.id == colorCategoryId,
    );
    
    final String categoryIcon = isEventOnly
        ? (entry.inlineCategoryIconDenorm ?? category?.icon ?? '📍')
        : (category?.icon ?? experience?.categoryIconDenorm ?? '?');
    
    final Color leadingBoxColor = colorCategory != null
        ? colorCategory.color.withOpacity(0.5)
        : isEventOnly && entry.inlineColorHexDenorm != null
            ? _parseColor(entry.inlineColorHexDenorm!).withOpacity(0.5)
            : experience?.colorHexDenorm != null &&
                    experience!.colorHexDenorm!.isNotEmpty
                ? _parseColor(experience.colorHexDenorm!).withOpacity(0.5)
                : Colors.white;
    
    final List<UserCategory> otherCategories = isEventOnly
        ? entry.inlineOtherCategoryIds
            .map((id) => widget.categories.firstWhereOrNull((cat) => cat.id == id))
            .whereType<UserCategory>()
            .toList()
        : (experience?.otherCategories
                .map((id) => widget.categories.firstWhereOrNull((cat) => cat.id == id))
                .whereType<UserCategory>()
                .toList() ??
            []);
    
    final List<ColorCategory> otherColorCategories = isEventOnly
        ? entry.inlineOtherColorCategoryIds
            .map((id) => widget.colorCategories.firstWhereOrNull((color) => color.id == id))
            .whereType<ColorCategory>()
            .toList()
        : (experience?.otherColorCategoryIds
                .map((id) => widget.colorCategories.firstWhereOrNull((color) => color.id == id))
                .whereType<ColorCategory>()
                .toList() ??
            []);
    
    final String? address = isEventOnly
        ? entry.inlineLocation?.address
        : experience?.location.address;
    final bool hasAddress = address != null && address.isNotEmpty;
    final bool hasOtherCategories = otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final bool hasNotes = (entry.note != null && entry.note!.isNotEmpty) ||
        (entry.transportInfo != null && entry.transportInfo!.isNotEmpty);
    
    // Event-only experiences don't have media
    final int contentCount = isEventOnly ? 0 : (experience?.sharedMediaItemIds.length ?? 0);
    final bool shouldShowSubRow =
        hasOtherCategories || hasOtherColorCategories || contentCount > 0 || isEventOnly || hasNotes;
    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;
    
    final List<Widget> subtitleChildren = [];
    if (hasAddress) {
      subtitleChildren.add(
        Text(
          address,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (shouldShowSubRow) {
      subtitleChildren.add(
        Padding(
          padding: EdgeInsets.only(top: hasAddress ? 2.0 : 0.0),
          child: Row(
            children: [
              if (hasNotes) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.note_outlined,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Has notes',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasOtherCategories || hasOtherColorCategories)
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 2.0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...otherCategories.map(
                            (otherCategory) => Text(
                              otherCategory.icon,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          ...otherColorCategories.map(
                            (otherColorCategory) => Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: otherColorCategory.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (experience != null) ...[
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Map button
                    Tooltip(
                      message: 'View Location on App Map',
                      child: ActionChip(
                        avatar: Image.asset(
                          'assets/icon/icon-cropped.png',
                          height: 18,
                        ),
                        label: const SizedBox.shrink(),
                        labelPadding: EdgeInsets.zero,
                        onPressed: () => _handleMapButtonPressed(experience),
                        tooltip: 'View Location on App Map',
                        backgroundColor: Colors.white,
                        shape: StadiumBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Directions button
                    Tooltip(
                      message: 'Get Directions',
                      child: ActionChip(
                        avatar: Icon(
                          Icons.directions_outlined,
                          color: Theme.of(context).primaryColor,
                          size: 18,
                        ),
                        label: const SizedBox.shrink(),
                        labelPadding: EdgeInsets.zero,
                        onPressed: () => _launchDirections(experience.location),
                        tooltip: 'Get Directions',
                        backgroundColor: Colors.white,
                        shape: StadiumBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                    // Play button (only if content exists)
                    if (contentCount > 0) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openExperienceContentPreview(experience),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: playButtonDiameter,
                              height: playButtonDiameter,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: playIconSize,
                              ),
                            ),
                            Positioned(
                              bottom: badgeOffset,
                              right: badgeOffset,
                              child: Container(
                                width: badgeDiameter,
                                height: badgeDiameter,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).primaryColor,
                                    width: badgeBorderWidth,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    contentCount.toString(),
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontSize: badgeFontSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (isEventOnly && entry.inlineLocation != null) ...[
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Map button
                    Tooltip(
                      message: 'View Location on App Map',
                      child: ActionChip(
                        avatar: Image.asset(
                          'assets/icon/icon-cropped.png',
                          height: 18,
                        ),
                        label: const SizedBox.shrink(),
                        labelPadding: EdgeInsets.zero,
                        onPressed: () => _handleEventOnlyMapButtonPressed(entry),
                        tooltip: 'View Location on App Map',
                        backgroundColor: Colors.white,
                        shape: StadiumBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Directions button
                    Tooltip(
                      message: 'Get Directions',
                      child: ActionChip(
                        avatar: Icon(
                          Icons.directions_outlined,
                          color: Theme.of(context).primaryColor,
                          size: 18,
                        ),
                        label: const SizedBox.shrink(),
                        labelPadding: EdgeInsets.zero,
                        onPressed: () => _launchDirections(entry.inlineLocation!),
                        tooltip: 'Get Directions',
                        backgroundColor: Colors.white,
                        shape: StadiumBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
              if (isEventOnly) ...[
                SizedBox(width: entry.inlineLocation != null ? 4 : 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Event-only',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final Widget leadingWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        const SizedBox(width: 4),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: leadingBoxColor,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text(
            categoryIcon,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ],
    );

    final String? scheduledTimeLabel = entry.scheduledTime != null
        ? _formatDateTime(entry.scheduledTime!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scheduledTimeLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Text(
              scheduledTimeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Card(
              key: ValueKey(entry.experienceId),
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.grey.shade100,
              child: ExpansionTile(
                shape: const RoundedRectangleBorder(
                  side: BorderSide(color: Colors.transparent, width: 0),
                  borderRadius: BorderRadius.zero,
                ),
                collapsedShape: const RoundedRectangleBorder(
                  side: BorderSide(color: Colors.transparent, width: 0),
                  borderRadius: BorderRadius.zero,
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8.0),
                childrenPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                leading: leadingWidget,
                title: Text(
                  displayName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                subtitle: subtitleChildren.isEmpty
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: subtitleChildren,
                      ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Scheduled Time
                        InkWell(
                          onTap: () => _editScheduledTime(entry, index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, right: 16.0),
                                  child: Icon(Icons.schedule, size: 24),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Scheduled time',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.scheduledTime != null
                                            ? _formatDateTime(entry.scheduledTime!)
                                            : 'Not set',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.grey[700],
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, left: 8.0),
                                  child: Icon(Icons.edit_outlined, size: 20),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Transport Info
                        InkWell(
                          onTap: () => _editTransportInfo(entry, index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, right: 16.0),
                                  child: Icon(Icons.directions, size: 24),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Transportation',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.transportInfo ?? 'Notes on how to get here',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.grey[700],
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, left: 8.0),
                                  child: Icon(Icons.edit_outlined, size: 20),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Note
                        InkWell(
                          onTap: () => _editNote(entry, index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, right: 16.0),
                                  child: Icon(Icons.note, size: 24),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Notes',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.note ?? 'None',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.grey[700],
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(top: 4.0, left: 8.0),
                                  child: Icon(Icons.edit_outlined, size: 20),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (!isEventOnly)
                              TextButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Open'),
                                onPressed: experience != null
                                    ? () => _openExperiencePage(experience)
                                    : null,
                              ),
                            if (isEventOnly)
                              TextButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                                onPressed: () => _editEventOnlyExperience(entry, index),
                              ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                              ),
                              icon: Icon(Icons.delete,
                                  color: Theme.of(context).primaryColor),
                              label: Text(
                                'Remove',
                                style: TextStyle(
                                    color: Theme.of(context).primaryColor),
                              ),
                              onPressed: () => _removeExperience(index),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: _buildExperienceIndexBadge(index),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExperienceIndexBadge(int index) {
    final Color badgeColor = Colors.grey.shade600;
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 9,
          ),
        ),
      ),
    );
  }

  Future<void> _openExperiencePage(Experience experience) async {
    if (!mounted) return;

    // Find the category for the experience
    final UserCategory? category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );

    // Build additional categories list
    final List<UserCategory> additionalCategories = experience.otherCategories
        .map((id) => widget.categories.firstWhereOrNull((cat) => cat.id == id))
        .whereType<UserCategory>()
        .toList();

    // Use fallback category if not found
    final UserCategory displayCategory = category ??
        UserCategory(
          id: 'unknown',
          name: 'Unknown',
          icon: '📍',
          ownerUserId: '',
        );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: experience,
          category: displayCategory,
          userColorCategories: widget.colorCategories,
          additionalUserCategories: additionalCategories,
        ),
      ),
    );
  }

  Future<void> _handleMapButtonPressed(Experience experience) async {
    if (!mounted) return;

    final Location locationForMap = _buildLocationForMapNavigation(experience);
    
    // Use the current event state (which may have unsaved changes)
    final eventToShow = _synchronizeCurrentEventFromControllers();

    final result = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialEvent: eventToShow,
          initialExperienceLocation: locationForMap,
        ),
      ),
    );

    // Handle returned event with updated itinerary
    if (result != null && mounted) {
      setState(() {
        _currentEvent = result;
        _markUnsavedChanges();
      });
    }
  }

  Future<void> _handleEventOnlyMapButtonPressed(EventExperienceEntry entry) async {
    if (!mounted || entry.inlineLocation == null) return;

    // Use the current event state (which may have unsaved changes)
    final eventToShow = _synchronizeCurrentEventFromControllers();

    final result = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialEvent: eventToShow,
          initialExperienceLocation: entry.inlineLocation!,
        ),
      ),
    );

    // Handle returned event with updated itinerary
    if (result != null && mounted) {
      setState(() {
        _currentEvent = result;
        _markUnsavedChanges();
      });
    }
  }

  Future<void> _openEventMapView() async {
    if (!mounted) return;

    // Use the current event state (which may have unsaved changes)
    final eventToShow = _synchronizeCurrentEventFromControllers();

    final result = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialEvent: eventToShow,
        ),
      ),
    );

    // Handle returned event with updated itinerary
    if (result != null && mounted) {
      setState(() {
        _currentEvent = result;
        _markUnsavedChanges();
      });
    }
  }

  Location _buildLocationForMapNavigation(Experience experience) {
    final Location location = experience.location;
    final String? displayName = location.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return location;
    }
    final String fallbackName = experience.name.trim();
    if (fallbackName.isEmpty) {
      return location;
    }
    return location.copyWith(displayName: fallbackName);
  }

  Future<void> _launchDirections(Location location) async {
    // Construct Google Maps directions URL (cross-platform)
    final lat = location.latitude;
    final lng = location.longitude;
    // Using address as destination query if available, otherwise lat/lng
    String query = (location.address != null && location.address!.isNotEmpty)
        ? Uri.encodeComponent(location.address!)
        : '$lat,$lng';

    final Uri mapUri =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');

    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('Could not launch $mapUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map directions.')),
        );
      }
    }
  }

  Future<void> _openExperienceContentPreview(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No saved content available yet for this experience.'),
          ),
        );
      }
      return;
    }

    final cachedItems = _experienceMediaCache[experience.id];
    late final List<SharedMediaItem> resolvedItems;

    if (cachedItems == null) {
      try {
        final fetched = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        resolvedItems = fetched;
        _experienceMediaCache[experience.id] = fetched;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load content preview: $e')),
          );
        }
        return;
      }
    } else {
      resolvedItems = cachedItems;
    }

    if (resolvedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No saved content available yet for this experience.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final UserCategory? category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (modalContext) {
        final SharedMediaItem initialMedia = resolvedItems.first;
        return SharedMediaPreviewModal(
          experience: experience,
          mediaItem: initialMedia,
          mediaItems: resolvedItems,
          onLaunchUrl: _launchUrl,
          category: category,
          userColorCategories: widget.colorCategories,
        );
      },
    );
  }

  Color _parseColor(String hexColor) {
    String normalized = hexColor.toUpperCase().replaceAll('#', '');
    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    }
    if (normalized.length == 8) {
      try {
        return Color(int.parse('0x$normalized'));
      } catch (_) {
        return Colors.white;
      }
    }
    return Colors.white;
  }

  Color _getEventColor(Event event) {
    // Use custom color if available, otherwise generate from event ID
    if (event.colorHex != null && event.colorHex!.isNotEmpty) {
      return _parseColor(event.colorHex!);
    }
    // Default color generation based on event ID
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];
    final hash = event.id.hashCode;
    return colors[hash.abs() % colors.length];
  }

  bool _isDarkColor(Color color) {
    // Calculate relative luminance (0 = dark, 1 = light)
    // Using the formula from WCAG guidelines
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance < 0.5;
  }

  Future<void> _pickEventColor() async {
    // Get current color (custom or default)
    final currentColor = _getEventColor(_currentEvent);
    
    final result = await _pickCustomColor(initialColor: currentColor);
    if (result != null && mounted) {
      // Remove "custom:" prefix if present
      final colorHex = result.startsWith('custom:') 
          ? result.substring(7) 
          : result;
      
      setState(() {
        _currentEvent = _currentEvent.copyWith(colorHex: colorHex);
        _markUnsavedChanges();
      });
    }
  }

  Future<void> _editScheduledTime(EventExperienceEntry entry, int index) async {
    final DateTime eventStart = _currentEvent.startDateTime;
    final DateTime eventEnd = _currentEvent.endDateTime.isBefore(eventStart)
        ? eventStart
        : _currentEvent.endDateTime;
    DateTime currentTime = entry.scheduledTime ?? eventStart;
    if (currentTime.isBefore(eventStart)) currentTime = eventStart;
    if (currentTime.isAfter(eventEnd)) currentTime = eventEnd;
    Widget wrapPicker(Widget? child) =>
        _wrapPickerWithWhiteTheme(context, child);

    final date = await showDatePicker(
      context: context,
      initialDate: currentTime,
      firstDate: eventStart,
      lastDate: eventEnd,
      builder: (ctx, child) => wrapPicker(child),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentTime),
      builder: (ctx, child) => wrapPicker(child),
    );
    if (time == null || !mounted) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (newDateTime.isBefore(eventStart) || newDateTime.isAfter(eventEnd)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Scheduled times must stay within the event timeframe.'),
          ),
        );
      }
      return;
    }

    setState(() {
      final entries =
          List<EventExperienceEntry>.from(_currentEvent.experiences);
      entries[index] = entry.copyWith(scheduledTime: newDateTime);
      _manuallyEditedScheduleIds.add(entry.experienceId);
      var updatedEvent = _currentEvent.copyWith(experiences: entries);
      updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
      _currentEvent = updatedEvent;
      _markUnsavedChanges();
    });
  }

  Future<void> _editTransportInfo(EventExperienceEntry entry, int index) async {
    final controller = TextEditingController(text: entry.transportInfo ?? '');

    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Transport Info'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g., Take subway line 1',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                // Return (true, value) to indicate save was pressed
                Navigator.of(ctx).pop((true, trimmed.isEmpty ? null : trimmed));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    // Only update if save was pressed (result is not null)
    if (result != null && mounted) {
      final (saved, value) = result;
      if (saved) {
        setState(() {
          final entries =
              List<EventExperienceEntry>.from(_currentEvent.experiences);
          entries[index] = entry.copyWith(
            transportInfo: value,
          );
          _currentEvent = _currentEvent.copyWith(experiences: entries);
          _markUnsavedChanges();
        });
      }
    }
  }

  Future<void> _editNote(EventExperienceEntry entry, int index) async {
    final controller = TextEditingController(text: entry.note ?? '');

    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Notes'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Add notes and details about this stop!',
                border: OutlineInputBorder(),
              ),
              minLines: 8,
              maxLines: 15,
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                // Return (true, value) to indicate save was pressed
                Navigator.of(ctx).pop((true, trimmed.isEmpty ? null : trimmed));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    // Only update if save was pressed (result is not null)
    if (result != null && mounted) {
      final (saved, value) = result;
      if (saved) {
        setState(() {
          final entries =
              List<EventExperienceEntry>.from(_currentEvent.experiences);
          entries[index] = entry.copyWith(
            note: value,
          );
          _currentEvent = _currentEvent.copyWith(experiences: entries);
          _markUnsavedChanges();
        });
      }
    }
  }

  void _removeExperience(int index) {
    setState(() {
      // Track the previous top-most experience ID
      final String? previousTopExperienceId = _currentEvent.experiences.isNotEmpty
          ? _currentEvent.experiences.first.experienceId
          : null;
      
      final entries =
          List<EventExperienceEntry>.from(_currentEvent.experiences);
      final removedEntry = entries.removeAt(index);
      _manuallyEditedScheduleIds.remove(removedEntry.experienceId);
      var updatedEvent = _currentEvent.copyWith(experiences: entries);
      updatedEvent = _eventWithAutoPrimarySchedule(updatedEvent);
      _currentEvent = updatedEvent;
      
      // Automatically update cover image from top-most experience if needed
      _updateCoverImageFromTopExperienceIfNeeded(
        previousTopExperienceId,
        updatedEvent.experiences,
      );
      
      _markUnsavedChanges();
    });
  }

  Event _eventWithAutoPrimarySchedule(Event event) {
    if (event.experiences.isEmpty) return event;
    final updatedEntries = List<EventExperienceEntry>.from(event.experiences);

    // Auto-set first entry time if not manually edited
    final firstEntry = updatedEntries.first;
    final DateTime start = event.startDateTime;
    final DateTime? currentTime = firstEntry.scheduledTime;
    final bool needsUpdate =
        !_manuallyEditedScheduleIds.contains(firstEntry.experienceId) &&
            (currentTime == null || !currentTime.isAtSameMomentAs(start));
    if (needsUpdate) {
      updatedEntries[0] = firstEntry.copyWith(scheduledTime: start);
    }

    // Sort entries by scheduled time (nulls go last, preserve relative order)
    updatedEntries.sort((a, b) {
      final aTime = a.scheduledTime;
      final bTime = b.scheduledTime;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final comparison = aTime.compareTo(bTime);
      if (comparison != 0) return comparison;
      return 0;
    });

    return event.copyWith(experiences: updatedEntries);
  }

  Widget _buildPeopleSection() {
    final planner = _userProfiles[_currentEvent.plannerUserId];
    final currentUserId = _authService.currentUser?.uid;
    final isPlanner = currentUserId == _currentEvent.plannerUserId;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'People',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          // Planner
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _buildUserAvatar(planner),
            title: Text(planner?.displayName ?? 'Loading...'),
            subtitle: const Text('Planner'),
          ),
          const SizedBox(height: 8),
          // Collaborators
          if (_currentEvent.collaboratorIds.isNotEmpty) ...[
            Text(
              'Collaborators',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _currentEvent.collaboratorIds.map((userId) {
                final profile = _userProfiles[userId];
                return Chip(
                  avatar: _buildUserAvatar(profile, size: 24),
                  label: Text(profile?.displayName ?? 'User'),
                  deleteIcon:
                      isPlanner ? const Icon(Icons.close, size: 18) : null,
                  onDeleted:
                      isPlanner ? () => _removeCollaborator(userId) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (isPlanner)
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Collaborators'),
              onPressed: _openAddCollaboratorsSheet,
            ),
          const SizedBox(height: 16),
          // Invited Users
          if (_currentEvent.invitedUserIds.isNotEmpty) ...[
            Text(
              'Viewers',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _currentEvent.invitedUserIds.map((userId) {
                final profile = _userProfiles[userId];
                return Chip(
                  avatar: _buildUserAvatar(profile, size: 24),
                  label: Text(profile?.displayName ?? 'User'),
                  deleteIcon:
                      isPlanner ? const Icon(Icons.close, size: 18) : null,
                  onDeleted:
                      isPlanner ? () => _removeInvitedUser(userId) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (isPlanner)
            OutlinedButton.icon(
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Add Viewers'),
              onPressed: _openInvitePeopleSheet,
            ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(UserProfile? profile, {double size = 40}) {
    if (profile?.photoURL != null && profile!.photoURL!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(profile.photoURL!),
      );
    }

    // Use first letter of display name with colored background
    final displayName = profile?.displayName ?? profile?.username ?? '?';
    final firstLetter =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final color = _getUserColor(profile?.id ?? '');

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        firstLetter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size / 2.5,
        ),
      ),
    );
  }

  Color _getUserColor(String userId) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];
    final hash = userId.hashCode.abs();
    return colors[hash % colors.length];
  }

  Future<void> _openAddCollaboratorsSheet() async {
    final String titleText = _titleController.text.trim();
    final Map<String, UserProfile> collaboratorProfiles = {
      for (final userId in _currentEvent.collaboratorIds)
        if (_userProfiles[userId] != null) userId: _userProfiles[userId]!,
    };
    final Map<String, String> disabledReasons = {
      for (final userId in _currentEvent.invitedUserIds)
        userId: 'Already invited to view',
    };
    await showShareToFriendsModal(
      context: context,
      onSubmit: (userIds) async {
        await _handleCollaboratorSelection(userIds);
      },
      subjectLabel: titleText.isEmpty ? null : titleText,
      titleText: 'Add collaborators with edit access',
      actionButtonLabel: 'Add',
      initialSelectedUserIds: _currentEvent.collaboratorIds,
      initialSelectedProfiles: collaboratorProfiles,
      disabledUserReasons: disabledReasons,
    );
  }

  Future<void> _openInvitePeopleSheet() async {
    final String titleText = _titleController.text.trim();
    final Map<String, UserProfile> inviteeProfiles = {
      for (final userId in _currentEvent.invitedUserIds)
        if (_userProfiles[userId] != null) userId: _userProfiles[userId]!,
    };
    final Map<String, String> disabledReasons = {
      for (final userId in _currentEvent.collaboratorIds)
        userId: 'Already has edit access',
    };

    await showShareToFriendsModal(
      context: context,
      onSubmit: (userIds) async {
        await _handleInviteSelection(userIds);
      },
      subjectLabel: titleText.isEmpty ? null : titleText,
      titleText: 'Add people with view access',
      actionButtonLabel: 'Invite',
      initialSelectedUserIds: _currentEvent.invitedUserIds,
      initialSelectedProfiles: inviteeProfiles,
      disabledUserReasons: disabledReasons,
    );
  }

  Future<void> _handleCollaboratorSelection(List<String> userIds) async {
    if (userIds.isEmpty) return;
    final List<String> updatedCollaborators =
        List<String>.from(_currentEvent.collaboratorIds);
    final List<String> newlyAdded = [];
    for (final userId in userIds) {
      if (userId == _currentEvent.plannerUserId) continue;
      if (updatedCollaborators.contains(userId)) continue;
      updatedCollaborators.add(userId);
      newlyAdded.add(userId);
    }

    if (newlyAdded.isEmpty) return;

    if (mounted) {
      setState(() {
        _currentEvent =
            _currentEvent.copyWith(collaboratorIds: updatedCollaborators);
        _markUnsavedChanges();
      });
    }

    await _ensureUserProfilesLoaded(newlyAdded);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newlyAdded.length == 1
              ? 'Collaborator added'
              : 'Collaborators added'),
        ),
      );
    }
  }

  Future<void> _handleInviteSelection(List<String> userIds) async {
    if (userIds.isEmpty) return;
    final List<String> updatedInvited =
        List<String>.from(_currentEvent.invitedUserIds);
    final List<String> newlyAdded = [];
    for (final userId in userIds) {
      if (userId == _currentEvent.plannerUserId) continue;
      if (updatedInvited.contains(userId)) continue;
      updatedInvited.add(userId);
      newlyAdded.add(userId);
    }

    if (newlyAdded.isEmpty) return;

    if (mounted) {
      setState(() {
        _currentEvent = _currentEvent.copyWith(invitedUserIds: updatedInvited);
        _markUnsavedChanges();
      });
    }

    await _ensureUserProfilesLoaded(newlyAdded);
  }

  Future<void> _ensureUserProfilesLoaded(List<String> userIds) async {
    if (userIds.isEmpty) return;
    final List<String> missing = userIds
        .where((id) => !_userProfiles.containsKey(id))
        .toList(growable: false);
    if (missing.isEmpty) return;

    final results = await Future.wait(
      missing.map((id) => _experienceService.getUserProfileById(id)),
    );

    if (!mounted) return;
    setState(() {
      for (int i = 0; i < missing.length; i++) {
        final profile = results[i];
        if (profile != null) {
          _userProfiles[missing[i]] = profile;
        }
      }
    });
  }

  void _removeCollaborator(String userId) {
    setState(() {
      final collaborators = List<String>.from(_currentEvent.collaboratorIds);
      collaborators.remove(userId);
      _currentEvent = _currentEvent.copyWith(collaboratorIds: collaborators);
      _markUnsavedChanges();
    });
  }

  void _removeInvitedUser(String userId) {
    setState(() {
      final invited = List<String>.from(_currentEvent.invitedUserIds);
      invited.remove(userId);
      _currentEvent = _currentEvent.copyWith(invitedUserIds: invited);
      _markUnsavedChanges();
    });
  }

  Widget _buildVisibilitySection() {
    final currentUserId = _authService.currentUser?.uid;
    final isPlanner = currentUserId == _currentEvent.plannerUserId;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visibility & Sharing',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          RadioListTile<EventVisibility>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private'),
            subtitle: const Text('Only you and collaborators'),
            value: EventVisibility.private,
            groupValue: _currentEvent.visibility,
            onChanged: isPlanner
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _currentEvent =
                            _currentEvent.copyWith(visibility: value);
                        _markUnsavedChanges();
                      });
                    }
                  }
                : null,
          ),
          RadioListTile<EventVisibility>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shared Link'),
            subtitle: const Text('Anyone with the link'),
            value: EventVisibility.sharedLink,
            groupValue: _currentEvent.visibility,
            onChanged: isPlanner
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _currentEvent =
                            _currentEvent.copyWith(visibility: value);
                        _markUnsavedChanges();
                      });
                    }
                  }
                : null,
          ),
          RadioListTile<EventVisibility>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Public'),
            subtitle: const Text('Discoverable by anyone'),
            value: EventVisibility.public,
            groupValue: _currentEvent.visibility,
            onChanged: isPlanner
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _currentEvent =
                            _currentEvent.copyWith(visibility: value);
                        _markUnsavedChanges();
                      });
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          if (isPlanner &&
              _currentEvent.id.isNotEmpty &&
              _currentEvent.visibility != EventVisibility.private) ...[
            if (_currentEvent.shareToken == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Generate Share Link'),
                onPressed: _generateShareLink,
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Share link: plendy.app/event/${_currentEvent.shareToken}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        // TODO: Copy to clipboard
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.link_off, color: Colors.red),
                label: const Text('Revoke Link',
                    style: TextStyle(color: Colors.red)),
                onPressed: _revokeShareLink,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _generateShareLink() async {
    try {
      final token = await _eventService.generateShareToken(_currentEvent.id);
      setState(() {
        _currentEvent = _currentEvent.copyWith(shareToken: token);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link generated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate link: $e')),
        );
      }
    }
  }

  Future<void> _revokeShareLink() async {
    try {
      await _eventService.revokeShareToken(_currentEvent.id);
      setState(() {
        _currentEvent = _currentEvent.copyWith(shareToken: null);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link revoked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to revoke link: $e')),
        );
      }
    }
  }

  Widget _buildCapacitySection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capacity & RSVPs',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _capacityController,
                  decoration: const InputDecoration(
                    labelText: 'Max capacity (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'No limit',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RSVPs'),
                    const SizedBox(height: 8),
                    Text(
                      '${_currentEvent.rsvpCount}${_currentEvent.capacity != null ? ' / ${_currentEvent.capacity}' : ''}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notifications',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<EventNotificationType>(
            value: _currentEvent.notificationPreference.type,
            decoration: const InputDecoration(
              labelText: 'Remind me',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: EventNotificationType.fiveMinutes,
                child: Text('5 minutes before'),
              ),
              DropdownMenuItem(
                value: EventNotificationType.fifteenMinutes,
                child: Text('15 minutes before'),
              ),
              DropdownMenuItem(
                value: EventNotificationType.thirtyMinutes,
                child: Text('30 minutes before'),
              ),
              DropdownMenuItem(
                value: EventNotificationType.oneHour,
                child: Text('1 hour before'),
              ),
              DropdownMenuItem(
                value: EventNotificationType.oneDay,
                child: Text('1 day before'),
              ),
              DropdownMenuItem(
                value: EventNotificationType.custom,
                child: Text('Custom...'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _currentEvent = _currentEvent.copyWith(
                    notificationPreference:
                        EventNotificationPreference(type: value),
                  );
                  _markUnsavedChanges();
                });

                if (value == EventNotificationType.custom) {
                  _showCustomDurationDialog();
                }
              }
            },
          ),
          if (_currentEvent.notificationPreference.type ==
                  EventNotificationType.custom &&
              _currentEvent.notificationPreference.customDuration != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Custom: ${_formatDuration(_currentEvent.notificationPreference.customDuration!)} before',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              hintText: 'Describe the vibe, schedule details, dress code, etc.',
              border: OutlineInputBorder(),
            ),
            minLines: 4,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomDurationDialog() async {
    int hours = 0;
    int minutes = 30;

    final result = await showDialog<Duration>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Custom Reminder'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Hours',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            hours = int.tryParse(value) ?? 0;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            minutes = int.tryParse(value) ?? 0;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final duration = Duration(hours: hours, minutes: minutes);
                    Navigator.of(ctx).pop(duration);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _currentEvent = _currentEvent.copyWith(
          notificationPreference: EventNotificationPreference(
            type: EventNotificationType.custom,
            customDuration: result,
          ),
        );
        _markUnsavedChanges();
      });
    }
  }

  Widget _buildCommentsSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comments (${_currentEvent.comments.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          if (_currentEvent.comments.isEmpty)
            const Text('No comments yet.', style: TextStyle(color: Colors.grey))
          else
            ...widget.event.comments.map((comment) {
              final author = _userProfiles[comment.authorId];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _buildUserAvatar(author, size: 36),
                title: Text(author?.displayName ?? 'User'),
                subtitle: Text(comment.text),
                trailing: Text(
                  _formatTimeAgo(comment.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_comment),
            label: const Text('Add Comment'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Add comment - not yet implemented')),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final String weekday = weekdayNames[dateTime.weekday - 1];
    return '$weekday, ${dateTime.month}/${dateTime.day}/${dateTime.year} ${_formatTime(TimeOfDay.fromDateTime(dateTime))}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
    if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
    if (minutes > 0)
      parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');

    return parts.isEmpty ? '0 minutes' : parts.join(', ');
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

/// Widget that animates sliding when an item's position in the list changes
class _SlidingItineraryItem extends StatefulWidget {
  final Widget child;
  final int index;

  const _SlidingItineraryItem({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  State<_SlidingItineraryItem> createState() => _SlidingItineraryItemState();
}

class _SlidingItineraryItemState extends State<_SlidingItineraryItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  int? _previousIndex;
  double _startOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.index;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _offsetAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ));

    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(_SlidingItineraryItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect position change
    if (_previousIndex != null && _previousIndex != widget.index) {
      final indexDelta = _previousIndex! - widget.index;
      // Each card is approximately 100 pixels (adjust based on your card height)
      // Positive indexDelta means moved up, negative means moved down
      _startOffset = indexDelta * 100.0;

      _offsetAnimation = Tween<double>(
        begin: _startOffset,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ));

      _controller.reset();
      _controller.forward();
    }

    _previousIndex = widget.index;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _offsetAnimation.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
