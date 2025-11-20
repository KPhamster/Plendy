import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/event.dart';
import '../models/experience.dart';
import '../models/user_profile.dart';
import '../services/event_service.dart';
import '../services/experience_service.dart';
import '../services/auth_service.dart';

/// Full-screen modal for editing event details
class EventEditorModal extends StatefulWidget {
  final Event event;
  final List<Experience> experiences; // Resolved experiences for the event

  const EventEditorModal({
    super.key,
    required this.event,
    required this.experiences,
  });

  @override
  State<EventEditorModal> createState() => _EventEditorModalState();
}

class _EventEditorModalState extends State<EventEditorModal> {
  final _eventService = EventService();
  final _experienceService = ExperienceService();
  final _authService = AuthService();
  
  late Event _currentEvent;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _coverImageUrlController;
  late TextEditingController _capacityController;
  
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  
  // User profiles cache
  final Map<String, UserProfile> _userProfiles = {};
  
  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    _titleController = TextEditingController(text: _currentEvent.title);
    _descriptionController = TextEditingController(text: _currentEvent.description);
    _coverImageUrlController = TextEditingController(text: _currentEvent.coverImageUrl ?? '');
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

      await _eventService.updateEvent(updatedEvent);
      
      setState(() {
        _currentEvent = updatedEvent;
        _hasUnsavedChanges = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event saved')),
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

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Do you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final Duration duration = _currentEvent.endDateTime.difference(_currentEvent.startDateTime);
    final String durationText = _formatDuration(duration);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _onWillPop()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
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
              TextButton(
                onPressed: _hasUnsavedChanges ? _saveEvent : null,
                child: Text(
                  'Save',
                  style: TextStyle(
                    color: _hasUnsavedChanges
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
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
                    Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
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
        return SafeArea(
          child: Wrap(
            children: [
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
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove image',
                      style: TextStyle(color: Colors.red)),
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
    final controller = TextEditingController(text: _coverImageUrlController.text);
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
          Row(
            children: [
              Expanded(
                child: _buildDateTimePicker(
                  label: 'Start',
                  dateTime: _currentEvent.startDateTime,
                  onChanged: (newDateTime) {
                    setState(() {
                      _currentEvent = _currentEvent.copyWith(
                        startDateTime: newDateTime,
                      );
                      _markUnsavedChanges();
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDateTimePicker(
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
                ),
              ),
            ],
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
  }) {
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
            Widget wrapPicker(Widget? child) => _wrapPickerWithWhiteTheme(context, child);

            final date = await showDatePicker(
              context: context,
              initialDate: dateTime,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              builder: (ctx, child) => wrapPicker(child),
            );
            if (date == null || !mounted) return;

            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(dateTime),
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
    final lighterPrimary = Color.lerp(primaryColor, Colors.white, 0.7) ?? primaryColor.withOpacity(0.3);
    
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
            return Colors.black87; // Unselected: dark text (same as hour/minute)
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
          Text(
            'Itinerary (${_currentEvent.experiences.length} experiences)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
                  final entry = entries.removeAt(oldIndex);
                  entries.insert(newIndex, entry);
                  _currentEvent = _currentEvent.copyWith(experiences: entries);
                  _markUnsavedChanges();
                });
              },
              itemBuilder: (context, index) {
                final entry = _currentEvent.experiences[index];
                final experience = widget.experiences.firstWhere(
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
                return _buildItineraryEntryCard(entry, experience, index);
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
    return Card(
      key: ValueKey(entry.experienceId),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(experience.name),
        subtitle: experience.location.address != null
            ? Text(experience.location.address!)
            : null,
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
                  title: const Text('Transport'),
                  subtitle: Text(entry.transportInfo ?? 'Not set'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editTransportInfo(entry, index),
                ),
                // Note
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.note),
                  title: const Text('Note'),
                  subtitle: Text(entry.note ?? 'Not set'),
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
                          const SnackBar(content: Text('Open experience - not yet implemented')),
                        );
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Remove', style: TextStyle(color: Colors.red)),
                      onPressed: () => _removeExperience(index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editScheduledTime(EventExperienceEntry entry, int index) async {
    final currentTime = entry.scheduledTime ?? _currentEvent.startDateTime;
    Widget wrapPicker(Widget? child) => _wrapPickerWithWhiteTheme(context, child);
    
    final date = await showDatePicker(
      context: context,
      initialDate: currentTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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

    setState(() {
      final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
      entries[index] = entry.copyWith(scheduledTime: newDateTime);
      _currentEvent = _currentEvent.copyWith(experiences: entries);
      _markUnsavedChanges();
    });
  }

  Future<void> _editTransportInfo(EventExperienceEntry entry, int index) async {
    final controller = TextEditingController(text: entry.transportInfo ?? '');
    
    final result = await showDialog<String>(
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
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
        entries[index] = entry.copyWith(
          transportInfo: result.isEmpty ? null : result,
        );
        _currentEvent = _currentEvent.copyWith(experiences: entries);
        _markUnsavedChanges();
      });
    }
  }

  Future<void> _editNote(EventExperienceEntry entry, int index) async {
    final controller = TextEditingController(text: entry.note ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Note'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Add a note for this stop...',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
        entries[index] = entry.copyWith(
          note: result.isEmpty ? null : result,
        );
        _currentEvent = _currentEvent.copyWith(experiences: entries);
        _markUnsavedChanges();
      });
    }
  }

  void _removeExperience(int index) {
    setState(() {
      final entries = List<EventExperienceEntry>.from(_currentEvent.experiences);
      entries.removeAt(index);
      _currentEvent = _currentEvent.copyWith(experiences: entries);
      _markUnsavedChanges();
    });
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
                  deleteIcon: isPlanner ? const Icon(Icons.close, size: 18) : null,
                  onDeleted: isPlanner
                      ? () => _removeCollaborator(userId)
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (isPlanner)
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Collaborator'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add collaborator - not yet implemented')),
                );
              },
            ),
          const SizedBox(height: 16),
          // Invited Users
          if (_currentEvent.invitedUserIds.isNotEmpty) ...[
            Text(
              'Invited',
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
                  deleteIcon: isPlanner ? const Icon(Icons.close, size: 18) : null,
                  onDeleted: isPlanner
                      ? () => _removeInvitedUser(userId)
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (isPlanner)
            OutlinedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Invite People'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite people - not yet implemented')),
                );
              },
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
    final firstLetter = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';
    
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
                        _currentEvent = _currentEvent.copyWith(visibility: value);
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
                        _currentEvent = _currentEvent.copyWith(visibility: value);
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
                        _currentEvent = _currentEvent.copyWith(visibility: value);
                        _markUnsavedChanges();
                      });
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          if (isPlanner) ...[
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
                label: const Text('Revoke Link', style: TextStyle(color: Colors.red)),
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                    notificationPreference: EventNotificationPreference(type: value),
                  );
                  _markUnsavedChanges();
                });
                
                if (value == EventNotificationType.custom) {
                  _showCustomDurationDialog();
                }
              }
            },
          ),
          if (_currentEvent.notificationPreference.type == EventNotificationType.custom &&
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
            const Text('No comments yet.',
                style: TextStyle(color: Colors.grey))
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
                const SnackBar(content: Text('Add comment - not yet implemented')),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month}/${dateTime.day}/${dateTime.year} ${_formatTime(TimeOfDay.fromDateTime(dateTime))}';
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
    if (minutes > 0) parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');

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
