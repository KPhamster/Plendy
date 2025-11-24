import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
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
        await _eventNotificationQueueService.queueEventNotifications(savedEvent);
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

        _popWithDraftResult(
          wasSaved: true,
          savedEvent: savedEvent,
          draftOverride: savedEvent,
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

    return WillPopScope(
      onWillPop: () async {
        _popWithDraftResult();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackNavigation,
          ),
          title: TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(
              hintText: 'Untitled Event',
              border: InputBorder.none,
            ),
          ),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isTimeRangeValid
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
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
    final String? newTopExperienceId = updatedEntries.isNotEmpty
        ? updatedEntries.first.experienceId
        : null;
    final bool topExperienceChanged = previousTopExperienceId != newTopExperienceId;
    if (!topExperienceChanged || newTopExperienceId == null) return;

    // Get the top-most experience and set cover image
    final topExperience = _availableExperiences.firstWhere(
      (exp) => exp.id == newTopExperienceId,
      orElse: () => Experience(
        id: newTopExperienceId,
        name: 'Unknown Experience',
        description: '',
        location: const Location(
          latitude: 0.0,
          longitude: 0.0,
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        editorUserIds: [],
      ),
    );

    final coverImageUrl = _buildCoverImageUrlFromExperience(topExperience);
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
            .map((entry) => MapEntry(
                  entry,
                  _availableExperiences
                      .firstWhereOrNull((exp) => exp.id == entry.experienceId),
                ))
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
                      final experience = itineraryExperiences[index].value;
                      final derivedUrl = experience != null
                          ? _buildCoverImageUrlFromExperience(experience)
                          : null;
                      final hasDerivedImage = derivedUrl != null;
                      final subtitle = experience?.location.getPlaceName();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: primaryColor.withOpacity(0.1),
                          foregroundColor: primaryColor,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(experience?.name ?? 'Unknown experience'),
                        subtitle: subtitle != null ? Text(subtitle) : null,
                        trailing: hasDerivedImage
                            ? const Icon(Icons.image, color: Colors.black54)
                            : const Text('No image',
                                style: TextStyle(color: Colors.grey)),
                        onTap: experience == null
                            ? null
                            : () {
                                if (!hasDerivedImage) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'No image available yet for ${experience.name}.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(sheetContext).pop();
                                if (!mounted) return;
                                setState(() {
                                  _coverImageUrlController.text = derivedUrl;
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

      final selectedOrder = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (ctx) => EventExperienceSelectorScreen(
            categories: widget.categories,
            colorCategories: widget.colorCategories,
            experiences: combinedExperiences,
            preSelectedExperienceIds: selectedIds.toSet(),
            title: 'Edit itinerary',
            returnSelectionOnly: true,
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

  List<EventExperienceEntry> _rebuildEntriesFromSelection(
      List<String> selectedIds) {
    final Map<String, EventExperienceEntry> existingEntries = {
      for (final entry in _currentEvent.experiences) entry.experienceId: entry,
    };
    
    // Track which existing entries we've already included
    final Set<String> includedExistingIds = {};
    
    // First, preserve existing entries in their current order
    final List<EventExperienceEntry> result = [];
    for (final entry in _currentEvent.experiences) {
      if (selectedIds.contains(entry.experienceId)) {
        result.add(entry);
        includedExistingIds.add(entry.experienceId);
      }
    }
    
    // Then, append new entries (not in existing list) in selection order
    for (final id in selectedIds) {
      if (!includedExistingIds.contains(id)) {
        result.add(existingEntries[id] ?? EventExperienceEntry(experienceId: id));
      }
    }
    
    return result;
  }

  Widget _buildScheduleSection(String durationText) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                message: 'Edit itinerary',
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
                final experience = _availableExperiences.firstWhere(
                  (exp) => exp.id == entry.experienceId,
                  orElse: () => Experience(
                    id: entry.experienceId,
                    name: 'Unknown Experience',
                    description: '',
                    location: const Location(
                      latitude: 0.0,
                      longitude: 0.0,
                    ),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                    editorUserIds: [],
                  ),
                );
                return _SlidingItineraryItem(
                  key: ValueKey(entry.experienceId),
                  index: index,
                  child: _buildItineraryEntryCard(entry, experience, index),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildItineraryEntryCard(
    EventExperienceEntry entry,
    Experience experience,
    int index,
  ) {
    final UserCategory? category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );
    final ColorCategory? colorCategory =
        widget.colorCategories.firstWhereOrNull(
      (color) => color.id == experience.colorCategoryId,
    );
    final String categoryIcon =
        category?.icon ?? experience.categoryIconDenorm ?? '?';
    final Color leadingBoxColor = colorCategory != null
        ? colorCategory.color.withOpacity(0.5)
        : experience.colorHexDenorm != null &&
                experience.colorHexDenorm!.isNotEmpty
            ? _parseColor(experience.colorHexDenorm!).withOpacity(0.5)
            : Colors.white;
    final List<UserCategory> otherCategories = experience.otherCategories
        .map((id) =>
            widget.categories.firstWhereOrNull((category) => category.id == id))
        .whereType<UserCategory>()
        .toList();
    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map((id) => widget.colorCategories
            .firstWhereOrNull((colorCategory) => colorCategory.id == id))
        .whereType<ColorCategory>()
        .toList();
    final String? address = experience.location.address;
    final bool hasAddress = address != null && address.isNotEmpty;
    final bool hasOtherCategories = otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final int contentCount = experience.sharedMediaItemIds.length;
    final bool shouldShowSubRow =
        hasOtherCategories || hasOtherColorCategories || contentCount > 0;
    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;

    final bool hasNotes = (entry.note != null && entry.note!.isNotEmpty) ||
        (entry.transportInfo != null && entry.transportInfo!.isNotEmpty);
    
    final List<Widget> subtitleChildren = [];
    if (hasAddress) {
      subtitleChildren.add(
        Text(
          address,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (hasNotes) {
      subtitleChildren.add(
        Padding(
          padding: EdgeInsets.only(top: hasAddress ? 4.0 : 0.0),
          child: Row(
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
        ),
      );
    }
    if (shouldShowSubRow) {
      subtitleChildren.add(
        Padding(
          padding: EdgeInsets.only(top: hasAddress ? 2.0 : 0.0),
          child: Row(
            children: [
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
              if (contentCount > 0) ...[
                const SizedBox(width: 12),
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
              experience.name,
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('Scheduled time'),
                      subtitle: Text(entry.scheduledTime != null
                          ? _formatDateTime(entry.scheduledTime!)
                          : 'Not set'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editScheduledTime(entry, index),
                    ),
                    // Transport Info
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.directions),
                      title: const Text('Transportation'),
                      subtitle: Text(entry.transportInfo ?? 'Notes on how to get here'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editTransportInfo(entry, index),
                    ),
                    // Note
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.note),
                      title: const Text('Notes'),
                      subtitle: Text(entry.note ?? 'None'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editNote(entry, index),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open'),
                          onPressed: () {
                            // TODO: Navigate to experience page
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Open experience - not yet implemented')),
                            );
                          },
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
      ],
    );
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
