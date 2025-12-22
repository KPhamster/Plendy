import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/event_editor_modal.dart';
import '../config/colors.dart';

/// Google Calendar-style events screen with Material 3 Expressive design
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _experienceService = ExperienceService();

  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final CalendarFormat _calendarFormat = CalendarFormat.month;

  // View mode: 'day', 'week', 'month', 'schedule'
  String _viewMode = 'schedule';

  // Events data
  List<Event> _allEvents = [];
  Map<DateTime, List<Event>> _eventsByDate = {};
  bool _isLoading = true;

  // Categories cache for looking up icons
  List<UserCategory> _categories = [];
  // Cache of ownerId+categoryId -> UserCategory for shared events
  final Map<String, UserCategory> _sharedOwnerCategories = {};
  
  // Experiences cache: maps experienceId to Experience
  final Map<String, Experience> _experiencesCache = {};

  late TabController _tabController;
  late PageController _weekPageController;
  int _currentTabIndex = 3;
  
  // Real-time event listeners
  final List<StreamSubscription> _eventSubscriptions = [];
  
  // Track events from each stream to properly handle removals
  final Map<String, Event> _plannerEvents = {};
  final Map<String, Event> _collaboratorEvents = {};
  final Map<String, Event> _invitedEvents = {};
  final ScrollController _scheduleScrollController = ScrollController();
  bool _scheduleDidInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 3);
    _tabController.addListener(() {
      if (_tabController.index != _currentTabIndex) {
        HapticFeedback.heavyImpact();
        _currentTabIndex = _tabController.index;
        setState(() {
          switch (_tabController.index) {
            case 0:
              _viewMode = 'day';
              break;
            case 1:
              _viewMode = 'week';
              break;
            case 2:
              _viewMode = 'month';
              break;
            case 3:
              _viewMode = 'schedule';
              _scheduleDidInitialScroll = false; // Reset to allow scroll on tab switch
              break;
          }
        });
      }
    });
    // Initialize week page controller at "current week" (middle of range)
    _weekPageController = PageController(initialPage: 52); // ~1 year range
    _loadCategories();
    _loadEvents();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _experienceService.getUserCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _weekPageController.dispose();
    _scheduleScrollController.dispose();
    // Cancel all real-time event listeners
    for (final subscription in _eventSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final userId = _authService.currentUser?.uid;
      debugPrint('EventsScreen: Loading events for user: $userId');
      
      if (userId != null) {
        // Cancel existing subscriptions
        for (final subscription in _eventSubscriptions) {
          subscription.cancel();
        }
        _eventSubscriptions.clear();
        
        // Set up real-time listeners for events where user is planner, collaborator, or invited
        final firestore = FirebaseFirestore.instance;
        final eventsCollection = firestore.collection('events');
        
        // Listen for events where user is the planner
        final plannerSubscription = eventsCollection
            .where('plannerUserId', isEqualTo: userId)
            .snapshots()
            .listen((snapshot) => _handleEventsSnapshot(snapshot, 'planner'));
        
        // Listen for events where user is a collaborator
        final collaboratorSubscription = eventsCollection
            .where('collaboratorIds', arrayContains: userId)
            .snapshots()
            .listen((snapshot) => _handleEventsSnapshot(snapshot, 'collaborator'));
        
        // Listen for events where user is invited
        final invitedSubscription = eventsCollection
            .where('invitedUserIds', arrayContains: userId)
            .snapshots()
            .listen((snapshot) => _handleEventsSnapshot(snapshot, 'invited'));
        
        _eventSubscriptions.addAll([
          plannerSubscription,
          collaboratorSubscription,
          invitedSubscription,
        ]);
        
        debugPrint('EventsScreen: Real-time listeners set up for user $userId');
        setState(() => _isLoading = false);
      } else {
        debugPrint('EventsScreen: No user logged in');
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading events: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() => _isLoading = false);
    }
  }
  
  void _handleEventsSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot, String streamType) {
    if (!mounted) return;
    
    try {
      // Update the appropriate map based on stream type
      Map<String, Event> targetMap;
      switch (streamType) {
        case 'planner':
          targetMap = _plannerEvents;
          break;
        case 'collaborator':
          targetMap = _collaboratorEvents;
          break;
        case 'invited':
          targetMap = _invitedEvents;
          break;
        default:
          debugPrint('Unknown stream type: $streamType');
          return;
      }
      
      // Clear and rebuild this stream's events
      targetMap.clear();
      
      // Parse events from this snapshot
      for (final doc in snapshot.docs) {
        try {
          targetMap[doc.id] = Event.fromMap(doc.data(), id: doc.id);
        } catch (e) {
          debugPrint('Error parsing event ${doc.id}: $e');
        }
      }
      
      // Merge all three streams, deduplicating by event ID
      final Map<String, Event> allEventsMap = {};
      allEventsMap.addAll(_plannerEvents);
      allEventsMap.addAll(_collaboratorEvents);
      allEventsMap.addAll(_invitedEvents);
      
      final events = allEventsMap.values.toList();
      events.sort((a, b) => b.startDateTime.compareTo(a.startDateTime));
      
      debugPrint('EventsScreen: Real-time update ($streamType) - ${events.length} total events');
      debugPrint('  Planner: ${_plannerEvents.length}, Collaborator: ${_collaboratorEvents.length}, Invited: ${_invitedEvents.length}');
      
      // Cache experiences referenced in events
      _cacheExperiencesForEvents(events);
      
      setState(() {
        _allEvents = events;
        _eventsByDate = _groupEventsByDate(events);
        // Don't reset scroll state here - let _buildScheduleView handle it
        // based on anchor event ID changes
      });
    } catch (e) {
      debugPrint('Error handling events snapshot: $e');
    }
  }

  Future<void> _cacheExperiencesForEvents(List<Event> events) async {
    // Collect all unique experience IDs from all events
    final experienceIds = <String>{};
    for (final event in events) {
      for (final entry in event.experiences) {
        if (entry.experienceId.isNotEmpty) {
          experienceIds.add(entry.experienceId);
        }
      }
    }

    // Fetch experiences that aren't already cached
    final idsToFetch = experienceIds
        .where((id) => !_experiencesCache.containsKey(id))
        .toList();

    if (idsToFetch.isNotEmpty) {
      try {
        final experiences = await _experienceService.getExperiencesByIds(idsToFetch);
        if (mounted) {
          setState(() {
            for (final exp in experiences) {
              _experiencesCache[exp.id] = exp;
            }
          });
        }
      } catch (e) {
        debugPrint('Error caching experiences: $e');
      }
    }

    // Collect owner/category pairs we need icons for (when denorm is missing)
    final Map<String, Set<String>> ownerToCategoryIds = {};
    for (final event in events) {
      for (final entry in event.experiences) {
        final exp = _experiencesCache[entry.experienceId];
        if (exp == null) continue;
        final ownerId = exp.createdBy ?? '';
        final categoryId = exp.categoryId ?? '';
        if (ownerId.isEmpty || categoryId.isEmpty) continue;
        final cacheKey = '${ownerId}_$categoryId';
        if (_sharedOwnerCategories.containsKey(cacheKey)) continue;
        ownerToCategoryIds.putIfAbsent(ownerId, () => <String>{}).add(categoryId);
      }
    }

    for (final entry in ownerToCategoryIds.entries) {
      try {
        final categories = await _experienceService.getUserCategoriesByOwnerAndIds(
          entry.key,
          entry.value.toList(),
        );
        if (categories.isNotEmpty && mounted) {
          setState(() {
            for (final category in categories) {
              final cacheKey = '${entry.key}_${category.id}';
              _sharedOwnerCategories[cacheKey] = category;
            }
          });
        }
      } catch (e) {
        debugPrint(
            'Error caching shared owner categories for ${entry.key}: $e');
      }
    }
  }

  Map<DateTime, List<Event>> _groupEventsByDate(List<Event> events) {
    final Map<DateTime, List<Event>> grouped = {};
    for (final event in events) {
      final date = DateTime(
        event.startDateTime.year,
        event.startDateTime.month,
        event.startDateTime.day,
      );
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(event);
    }
    return grouped;
  }

  List<Event> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _eventsByDate[normalizedDay] ?? [];
  }

  void _createNewEvent() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    final newEvent = Event(
      id: '',
      title: '',
      description: '',
      startDateTime: _selectedDay,
      endDateTime: _selectedDay.add(const Duration(hours: 1)),
      plannerUserId: userId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Show loading indicator
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch user's categories and color categories
      final experienceService = ExperienceService();
      final categories = await experienceService.getUserCategories();
      final colorCategories = await experienceService.getUserColorCategories();

      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();

      final result = await Navigator.push<EventEditorResult>(
        context,
        MaterialPageRoute(
          builder: (context) => EventEditorModal(
            event: newEvent,
            experiences: const [],
            categories: categories,
            colorCategories: colorCategories,
          ),
          fullscreenDialog: true,
        ),
      );

      // Refresh immediately if event was saved
      if (result != null && result.wasSaved) {
        // Refresh events list to reflect changes immediately
        await _loadEvents();
      }
    } catch (e) {
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _goToToday() {
    setState(() {
      _focusedDay = DateTime.now();
      _selectedDay = DateTime.now();
    });
    
    // Handle different views
    if (_viewMode == 'schedule') {
      // If on Schedule tab, scroll to today's event
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollScheduleToToday();
      });
    } else if (_viewMode == 'week') {
      // If on Week tab, navigate to this week
      _weekPageController.animateToPage(
        52, // Page 52 is the current week
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  void _navigateWeekToMonth(DateTime selectedDate) {
    // Calculate the first day of the selected month
    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    
    // Calculate the week start (Sunday) for that month
    // If the first day is not a Sunday, get the next Sunday for the first full week
    final dayOfWeek = firstDayOfMonth.weekday;
    final daysUntilSunday = (7 - dayOfWeek) % 7;
    
    final firstFullWeekStart = daysUntilSunday == 0
        ? firstDayOfMonth
        : firstDayOfMonth.add(Duration(days: daysUntilSunday));
    
    // Calculate which page this week corresponds to
    // Page 52 is the current week, so we calculate the offset
    final now = DateTime.now();
    final currentWeekStart = now.subtract(
      Duration(days: now.weekday % 7),
    );
    
    // Calculate the number of weeks between currentWeekStart and firstFullWeekStart
    final weekDifference = firstFullWeekStart.difference(currentWeekStart).inDays ~/ 7;
    final targetPage = 52 + weekDifference;
    
    debugPrint(
      'Week: Navigating to month ${selectedDate.month}/${selectedDate.year}, '
      'first full week: ${DateFormat('MMM d').format(firstFullWeekStart)}, '
      'page: $targetPage',
    );
    
    _weekPageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollScheduleToToday() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    
    final events = [..._allEvents]..sort(
      (a, b) => a.startDateTime.compareTo(b.startDateTime),
    );
    if (events.isEmpty) return;
    
    // Find first event on or after today
    int targetIndex = events.indexWhere(
      (event) => !event.startDateTime.isBefore(todayStart),
    );
    
    // If no events on or after today, use the last event
    if (targetIndex == -1) {
      targetIndex = events.length - 1;
    }
    
    debugPrint(
      'Schedule: Scrolling to today (index $targetIndex)',
    );
    _scrollScheduleToIndex(events, targetIndex, reason: 'today');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEvent,
        tooltip: 'Add Event',
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(theme, isDark),
            _buildViewTabs(theme, isDark),
            Expanded(
              child: Container(
                color: AppColors.backgroundColorMid,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildViewContent(theme, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Month/Year display
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                _showMonthPicker(context);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      DateFormat('MMMM y').format(_focusedDay),
                      style: GoogleFonts.notoSerif(
                        textStyle: theme.textTheme.headlineSmall,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ],
              ),
            ),
          ),
          // Today button
          TextButton.icon(
            onPressed: () {
              HapticFeedback.heavyImpact();
              _goToToday();
            },
            icon: const Icon(Icons.today_outlined),
            label: const Text('Today'),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search icon
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context, theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTabs(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        indicatorColor: theme.colorScheme.primary,
        indicatorWeight: 3,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'Google Sans',
        ),
        tabs: const [
          Tab(text: 'Day'),
          Tab(text: 'Week'),
          Tab(text: 'Month'),
          Tab(text: 'Schedule'),
        ],
      ),
    );
  }

  Widget _buildViewContent(ThemeData theme, bool isDark) {
    switch (_viewMode) {
      case 'day':
        return _buildDayView(theme, isDark);
      case 'week':
        return _buildWeekView(theme, isDark);
      case 'schedule':
        return _buildScheduleView(theme, isDark);
      case 'month':
      default:
        return _buildMonthView(theme, isDark);
    }
  }

  Widget _buildMonthView(ThemeData theme, bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: Column(
        children: [
          // Calendar widget
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2B2930) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
            ),
            child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: _calendarFormat,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            calendarStyle: CalendarStyle(
              // Today decoration
              todayDecoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              // Selected day decoration
              selectedDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              // Weekend styling
              weekendTextStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              // Event markers
              markersMaxCount: 3,
              markerDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerSize: 6,
              markersAlignment: Alignment.bottomCenter,
              // Rounded corners feel
              cellMargin: const EdgeInsets.all(4),
              cellPadding: const EdgeInsets.all(0),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: false,
              leftChevronVisible: false,
              rightChevronVisible: false,
              titleTextStyle: const TextStyle(fontSize: 0), // Hidden
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
          ),
        ),
        // Events list for selected day
        Expanded(
          child: _buildEventsList(
            _getEventsForDay(_selectedDay),
            theme,
            isDark,
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildDayView(ThemeData theme, bool isDark) {
    final events = _getEventsForDay(_selectedDay);
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Swipe left to go to next day
          if (details.primaryVelocity! < 0) {
            setState(() {
              _selectedDay = _selectedDay.add(const Duration(days: 1));
              _focusedDay = _selectedDay;
            });
          }
          // Swipe right to go to previous day
          else if (details.primaryVelocity! > 0) {
            setState(() {
              _selectedDay = _selectedDay.subtract(const Duration(days: 1));
              _focusedDay = _selectedDay;
            });
          }
        },
        child: Column(
          children: [
            // Day header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _selectedDay = _selectedDay.subtract(const Duration(days: 1));
                        _focusedDay = _selectedDay;
                      });
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat('EEEE, MMMM d, y').format(_selectedDay),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _selectedDay = _selectedDay.add(const Duration(days: 1));
                        _focusedDay = _selectedDay;
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildEventsList(events, theme, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Swipe hint
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chevron_left,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 8),
              Text(
                'Swipe to change week',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _weekPageController,
            onPageChanged: (page) {
              // Calculate the start of week for this page
              // Page 52 is the current week, each page is 7 days apart
              final now = DateTime.now();
              final currentWeekStart = now.subtract(
                Duration(days: now.weekday % 7),
              );
              final weekOffset = page - 52;
              final newWeekStart = currentWeekStart.add(
                Duration(days: weekOffset * 7),
              );
              
              setState(() {
                _selectedDay = newWeekStart;
                _focusedDay = newWeekStart;
              });
            },
            itemCount: 104, // ~2 years of weeks (52 weeks * 2)
            itemBuilder: (context, page) {
              // Calculate week start for this page
              final now = DateTime.now();
              final currentWeekStart = now.subtract(
                Duration(days: now.weekday % 7),
              );
              final weekOffset = page - 52;
              final weekStart = currentWeekStart.add(
                Duration(days: weekOffset * 7),
              );

              return RefreshIndicator(
                onRefresh: _loadEvents,
                child: Column(
                  children: [
                    // Week header with days
                    _buildWeekHeader(weekStart, theme, isDark),
                    // Weekly grid
                    Expanded(
                      child: _buildWeeklyGrid(weekStart, theme, isDark),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(DateTime startOfWeek, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Time column header (empty space)
          const SizedBox(width: 50),
          // Day headers
          ...List.generate(7, (index) {
            final day = startOfWeek.add(Duration(days: index));
            final isToday = isSameDay(day, DateTime.now());

            return Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('E').format(day),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isToday
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isToday
                              ? Colors.white
                              : isDark
                                  ? Colors.white
                                  : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWeeklyGrid(DateTime startOfWeek, ThemeData theme, bool isDark) {
    // Get events for the week grouped by day
    final weekEvents = <DateTime, List<Event>>{};
    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      final normalizedDay = DateTime(day.year, day.month, day.day);
      weekEvents[normalizedDay] = _getEventsForDay(day);
    }

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time labels column
          _buildTimeLabelsColumn(theme, isDark),
          // Day columns
          ...List.generate(7, (index) {
            final day = startOfWeek.add(Duration(days: index));
            final normalizedDay = DateTime(day.year, day.month, day.day);
            final events = weekEvents[normalizedDay] ?? [];
            
            return Expanded(
              child: _buildDayColumn(day, events, theme, isDark),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimeLabelsColumn(ThemeData theme, bool isDark) {
    return SizedBox(
      width: 50,
      child: Column(
        children: List.generate(24, (hour) {
          return Container(
            height: 60,
            alignment: Alignment.topRight,
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: Text(
              hour == 0
                  ? '12 AM'
                  : hour < 12
                      ? '$hour AM'
                      : hour == 12
                          ? '12 PM'
                          : '${hour - 12} PM',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(DateTime day, List<Event> events, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Stack(
        children: [
          // Hour grid lines
          Column(
            children: List.generate(24, (hour) {
              return Container(
                height: 60,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                ),
              );
            }),
          ),
          // Events positioned by time
          ...events.map((event) => _buildWeekEventCard(event, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildWeekEventCard(Event event, ThemeData theme, bool isDark) {
    final startHour = event.startDateTime.hour + (event.startDateTime.minute / 60);
    final endHour = event.endDateTime.hour + (event.endDateTime.minute / 60);
    final duration = endHour - startHour;
    
    // Calculate position and height
    final top = startHour * 60.0; // 60px per hour
    final height = (duration * 60.0).clamp(30.0, double.infinity); // Min 30px

    final eventColor = _getEventColor(event);

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          _openEventDetails(event);
        },
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: eventColor.withOpacity(0.2),
            border: Border(
              left: BorderSide(
                color: eventColor,
                width: 3,
              ),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title.isEmpty ? 'Untitled' : event.title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (height > 40)
                Text(
                  DateFormat('h:mm a').format(event.startDateTime),
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleView(ThemeData theme, bool isDark) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final events = [..._allEvents]..sort(
      (a, b) => a.startDateTime.compareTo(b.startDateTime),
    );
    final anchorIndex = events.indexWhere(
      (event) => !event.startDateTime.isBefore(todayStart),
    );
    final targetIndex = anchorIndex == -1 && events.isNotEmpty
        ? events.length - 1
        : anchorIndex;

    debugPrint('Schedule: Building with ${events.length} events, anchor index: $targetIndex');
    if (targetIndex != -1 && targetIndex < events.length) {
      debugPrint('Schedule: Anchor event: "${events[targetIndex].title}" at ${events[targetIndex].startDateTime}');
    }

    // Scroll to the anchor event by calculating offset
    if (targetIndex != -1 && !_scheduleDidInitialScroll) {
      debugPrint('Schedule: Scheduling scroll to index $targetIndex');
      _scheduleDidInitialScroll = true;
      _scrollScheduleToIndex(events, targetIndex, reason: 'initial');
    }

    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          controller: _scheduleScrollController,
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 64,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No upcoming events',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final scheduleEntries = <Widget>[];
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final showDateHeader = index == 0 ||
          !isSameDay(
            event.startDateTime,
            events[index - 1].startDateTime,
          );

      scheduleEntries.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  _formatDateHeader(event.startDateTime),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            _buildEventCard(
              event,
              theme,
              isDark,
            ),
          ],
        ),
      );
    }

    // Add bottom padding so any event can scroll to the top of the viewport
    // This ensures the last events don't get stuck at the bottom
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    // App bar (~64px) + Tab bar (~48px) + safe area padding
    final toolbarHeight = 64 + 48 + safeAreaTop;
    // Available viewport height for scrolling content
    final viewportHeight = screenHeight - toolbarHeight - safeAreaBottom;
    // Add padding equal to viewport height minus a small buffer for one event
    final bottomPadding = (viewportHeight - 150).clamp(200.0, double.infinity);
    
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView(
        controller: _scheduleScrollController,
        padding: EdgeInsets.only(top: 8, bottom: bottomPadding),
        children: scheduleEntries,
      ),
    );
  }

  void _scrollScheduleToIndex(
    List<Event> events,
    int targetIndex, {
    String reason = 'manual',
  }) {
    if (targetIndex < 0 || targetIndex >= events.length) return;

    void attemptScroll([int attempts = 0]) {
      if (attempts >= 10) {
        debugPrint('Schedule: Max scroll attempts reached for $reason');
        return;
      }

      if (!_scheduleScrollController.hasClients) {
        debugPrint('Schedule: No scroll clients yet for $reason (attempt ${attempts + 1}), retrying...');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          attemptScroll(attempts + 1);
        });
        return;
      }

      final offset = _calculateScheduleOffset(events, targetIndex);
      debugPrint(
        'Schedule: Scrolling ($reason) to index $targetIndex at offset $offset '
        '(max: ${_scheduleScrollController.position.maxScrollExtent})',
      );

      _scheduleScrollController.animateTo(
        offset.clamp(0.0, _scheduleScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      attemptScroll();
    });
  }

  double _calculateScheduleOffset(List<Event> events, int targetIndex) {
    double offset = 0;
    for (int i = 0; i < targetIndex; i++) {
      final event = events[i];
      final showDateHeader = i == 0 ||
          !isSameDay(
            event.startDateTime,
            events[i - 1].startDateTime,
          );

      if (showDateHeader) {
        offset += 50; // Date header height
      }

      offset += 110; // Estimated card height with padding
    }

    if (targetIndex > 0 &&
        !isSameDay(
          events[targetIndex].startDateTime,
          events[targetIndex - 1].startDateTime,
        )) {
      offset += 50;
    }

    return offset;
  }

  void _scrollScheduleToMonth(DateTime selectedDate) {
    if (_viewMode != 'schedule') return;

    final events = [..._allEvents]..sort(
      (a, b) => a.startDateTime.compareTo(b.startDateTime),
    );
    if (events.isEmpty) return;

    final targetIndex = _findEventIndexForMonth(events, selectedDate);
    if (targetIndex == -1) return;

    debugPrint(
      'Schedule: Scrolling to month ${selectedDate.month}/${selectedDate.year} (index $targetIndex)',
    );
    _scrollScheduleToIndex(events, targetIndex, reason: 'month');
  }

  int _findEventIndexForMonth(List<Event> events, DateTime selectedDate) {
    if (events.isEmpty) return -1;

    final targetMonthStart = DateTime(selectedDate.year, selectedDate.month, 1);
    int? monthIndex;
    int? nearestIndex;
    int? nearestDistanceMinutes;

    for (int i = 0; i < events.length; i++) {
      final eventDate = events[i].startDateTime;

      if (eventDate.year == targetMonthStart.year &&
          eventDate.month == targetMonthStart.month) {
        monthIndex = i;
        break;
      }

      final distanceMinutes =
          eventDate.difference(targetMonthStart).inMinutes.abs();
      final isCloser = nearestDistanceMinutes == null ||
          distanceMinutes < nearestDistanceMinutes;
      final isEquallyCloseButFuture = nearestDistanceMinutes != null &&
          distanceMinutes == nearestDistanceMinutes &&
          !eventDate.isBefore(targetMonthStart);

      if (isCloser || isEquallyCloseButFuture) {
        nearestDistanceMinutes = distanceMinutes;
        nearestIndex = i;
      }
    }

    return monthIndex ?? nearestIndex ?? -1;
  }


  Widget _buildEventsList(List<Event> events, ThemeData theme, bool isDark) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_outlined,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'No events',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _createNewEvent,
              icon: const Icon(Icons.add),
              label: const Text('Create Event'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) => _buildEventCard(
        events[index],
        theme,
        isDark,
      ),
    );
  }

  Widget _buildEventCard(
    Event event,
    ThemeData theme,
    bool isDark, {
    Key? key,
  }) {
    final cardColor = isDark
        ? const Color(0xFF2B2930)
        : Colors.white;
    final borderColor = _getEventColor(event);

    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        _openEventDetails(event);
      },
      child: Container(
        key: key,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Colored left border
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              // Event content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        event.title.isEmpty ? 'Untitled Event' : event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Google Sans',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Time
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatEventTime(event),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      // Description (if available)
                      if (event.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          event.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Experience count with category icons
                      if (event.experiences.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${event.experiences.length} experience${event.experiences.length != 1 ? 's' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Category icons with overflow handling
                            Flexible(
                              child: _buildTruncatedCategoryIcons(event.experiences),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEventDetails(Event event) async {
    // Show loading indicator
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch the experiences referenced in the event
      // Filter out empty strings (event-only experiences have empty experienceId)
      final experienceIds = event.experiences
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();
      
      final experienceService = ExperienceService();
      
      List<Experience> experiences = [];
      if (experienceIds.isNotEmpty) {
        experiences = await experienceService.getExperiencesByIds(experienceIds);
      }

      // Fetch the category + color metadata from the event owner so shared viewers
      // see the same icons/colors as the planner.
      final userId = _authService.currentUser?.uid;
      final bool isOwner = userId != null && event.plannerUserId == userId;

      List<UserCategory> categories = [];
      List<ColorCategory> colorCategories = [];

      if (isOwner) {
        categories = await experienceService.getUserCategories();
        colorCategories = await experienceService.getUserColorCategories();
      } else {
        final Set<String> categoryIds = {};
        final Set<String> colorCategoryIds = {};

        for (final exp in experiences) {
          if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
            categoryIds.add(exp.categoryId!);
          }
          categoryIds.addAll(
              exp.otherCategories.where((id) => id.isNotEmpty));

          if (exp.colorCategoryId != null &&
              exp.colorCategoryId!.isNotEmpty) {
            colorCategoryIds.add(exp.colorCategoryId!);
          }
          colorCategoryIds
              .addAll(exp.otherColorCategoryIds.where((id) => id.isNotEmpty));
        }

        for (final entry in event.experiences) {
          if (entry.inlineCategoryId != null &&
              entry.inlineCategoryId!.isNotEmpty) {
            categoryIds.add(entry.inlineCategoryId!);
          }
          categoryIds.addAll(
              entry.inlineOtherCategoryIds.where((id) => id.isNotEmpty));

          if (entry.inlineColorCategoryId != null &&
              entry.inlineColorCategoryId!.isNotEmpty) {
            colorCategoryIds.add(entry.inlineColorCategoryId!);
          }
          colorCategoryIds.addAll(entry.inlineOtherColorCategoryIds
              .where((id) => id.isNotEmpty));
        }

        try {
          if (categoryIds.isNotEmpty) {
            categories =
                await experienceService.getUserCategoriesByOwnerAndIds(
              event.plannerUserId,
              categoryIds.toList(),
            );
          }
        } catch (e) {
          debugPrint(
              'EventsScreen: Failed to fetch planner categories for event ${event.id}: $e');
        }

        try {
          if (colorCategoryIds.isNotEmpty) {
            colorCategories =
                await experienceService.getColorCategoriesByOwnerAndIds(
              event.plannerUserId,
              colorCategoryIds.toList(),
            );
          }
        } catch (e) {
          debugPrint(
              'EventsScreen: Failed to fetch planner color categories for event ${event.id}: $e');
        }

        // Fallback to current user's categories if nothing was fetched
        if (categories.isEmpty) {
          categories = await experienceService.getUserCategories();
        }
        if (colorCategories.isEmpty) {
          colorCategories = await experienceService.getUserColorCategories();
        }
      }
      
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();

      final result = await Navigator.push<EventEditorResult>(
        context,
        MaterialPageRoute(
          builder: (context) => EventEditorModal(
            event: event,
            experiences: experiences,
            categories: categories,
            colorCategories: colorCategories,
            isReadOnly: true,
          ),
          fullscreenDialog: true,
        ),
      );

      // Refresh immediately if event was saved
      if (result != null && result.wasSaved) {
        // Refresh events list to reflect changes immediately
        await _loadEvents();
      }
    } catch (e) {
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading event details: $e')),
      );
    }
  }

  Color _getEventColor(Event event) {
    // Use custom color if available, otherwise generate from event ID
    if (event.colorHex != null && event.colorHex!.isNotEmpty) {
      return _parseColor(event.colorHex!);
    }
    // Default color generation based on event ID for consistency
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

  Color _parseColor(String hexColor) {
    String normalized = hexColor.toUpperCase().replaceAll('#', '');
    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    }
    if (normalized.length == 8) {
      try {
        return Color(int.parse('0x$normalized'));
      } catch (_) {
        return Colors.blue; // Fallback to blue
      }
    }
    return Colors.blue; // Fallback to blue
  }

  String _formatEventTime(Event event) {
    final start = DateFormat('h:mm a').format(event.startDateTime);
    final end = DateFormat('h:mm a').format(event.endDateTime);
    
    if (isSameDay(event.startDateTime, event.endDateTime)) {
      return '$start - $end';
    } else {
      return '$start - ${DateFormat('MMM d, h:mm a').format(event.endDateTime)}';
    }
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final yesterday = now.subtract(const Duration(days: 1));

    if (isSameDay(date, now)) {
      return 'Today • ${DateFormat('EEEE, MMMM d').format(date)}';
    } else if (isSameDay(date, tomorrow)) {
      return 'Tomorrow • ${DateFormat('EEEE, MMMM d').format(date)}';
    } else if (isSameDay(date, yesterday)) {
      return 'Yesterday • ${DateFormat('EEEE, MMMM d').format(date)}';
    } else {
      return DateFormat('EEEE, MMMM d').format(date);
    }
  }

  void _showMonthPicker(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1B1F) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MonthYearPickerSheet(
        initialDate: _focusedDay,
        onDateSelected: (selectedDate) {
          setState(() {
            _focusedDay = selectedDate;
            _selectedDay = selectedDate;
          });
          Navigator.of(context).pop();
          if (_viewMode == 'schedule') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollScheduleToMonth(selectedDate);
            });
          } else if (_viewMode == 'week') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigateWeekToMonth(selectedDate);
            });
          }
        },
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Build truncated category icons with overflow handling
  Widget _buildTruncatedCategoryIcons(List<EventExperienceEntry> entries) {
    final icons = entries
        .map((entry) => _getCategoryIconForEntry(entry))
        .where((icon) => icon != null)
        .cast<String>()
        .toList();

    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }

    // Simple approach: show icons with ellipsis
    // This handles overflow naturally without LayoutBuilder
    return Text(
      icons.join(' '),
      style: const TextStyle(fontSize: 14),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }

  /// Get category icon for an EventExperienceEntry
  /// Returns null if no icon is available
  String? _getCategoryIconForEntry(EventExperienceEntry entry) {
    // For event-only experiences, use the denormalized icon
    if (entry.isEventOnly) {
      return entry.inlineCategoryIconDenorm?.isNotEmpty == true
          ? entry.inlineCategoryIconDenorm
          : '📍'; // Fallback icon
    }

    // For regular experiences, get from cached Experience object
    final experience = _experiencesCache[entry.experienceId];
    if (experience != null) {
      // First try denormalized icon
      if (experience.categoryIconDenorm != null &&
          experience.categoryIconDenorm!.isNotEmpty) {
        return experience.categoryIconDenorm;
      }

      // Then try looking up by categoryId
      if (experience.categoryId != null && experience.categoryId!.isNotEmpty) {
        final ownerId = experience.createdBy ?? '';
        if (ownerId.isNotEmpty) {
          final cacheKey = '${ownerId}_${experience.categoryId}';
          final sharedCategory = _sharedOwnerCategories[cacheKey];
          if (sharedCategory != null && sharedCategory.icon.isNotEmpty) {
            return sharedCategory.icon;
          }
        }

        try {
          final category = _categories.firstWhere(
            (cat) => cat.id == experience.categoryId,
          );
          if (category.icon.isNotEmpty) {
            return category.icon;
          }
        } catch (_) {
          // Category not found in user's categories
        }
      }
    }

    return null; // No icon available
  }

  void _showSearchDialog(BuildContext context, ThemeData theme, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => _EventSearchDialog(
        events: _allEvents,
        experiencesCache: _experiencesCache,
        theme: theme,
        isDark: isDark,
        onEventSelected: (event) {
          Navigator.of(context).pop();
          _scrollToEventFromSearch(event);
        },
      ),
    );
  }

  void _scrollToEventFromSearch(Event event) {
    final events = [..._allEvents]..sort(
      (a, b) => a.startDateTime.compareTo(b.startDateTime),
    );
    
    final targetIndex = events.indexWhere((e) => e.id == event.id);
    if (targetIndex != -1) {
      // Switch to schedule view if not already there
      if (_viewMode != 'schedule') {
        _tabController.animateTo(3);
      }
      
      // Schedule the scroll for the next frame to ensure we're on the schedule view
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollScheduleToIndex(events, targetIndex, reason: 'search');
      });
    }
  }
}

/// Search dialog for events and their experiences
class _EventSearchDialog extends StatefulWidget {
  final List<Event> events;
  final Map<String, Experience> experiencesCache;
  final ThemeData theme;
  final bool isDark;
  final Function(Event) onEventSelected;

  const _EventSearchDialog({
    required this.events,
    required this.experiencesCache,
    required this.theme,
    required this.isDark,
    required this.onEventSelected,
  });

  @override
  State<_EventSearchDialog> createState() => _EventSearchDialogState();
}

class _EventSearchDialogState extends State<_EventSearchDialog> {
  late TextEditingController _searchController;
  List<_SearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_performSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _searchController.text.toLowerCase();
    
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final results = <_SearchResult>[];
    
    for (final event in widget.events) {
      // Search in event title
      if (event.title.toLowerCase().contains(query)) {
        results.add(_SearchResult(
          event: event,
          matchType: 'event',
          matchText: event.title,
        ));
      }
      
      // Search in event description
      if (event.description.isNotEmpty && 
          event.description.toLowerCase().contains(query)) {
        results.add(_SearchResult(
          event: event,
          matchType: 'description',
          matchText: event.description,
        ));
      }
      
      // Search in experiences
      for (final entry in event.experiences) {
        if (entry.experienceId.isEmpty) {
          // Event-only experience
          if (entry.inlineName != null &&
              entry.inlineName!.isNotEmpty &&
              entry.inlineName!.toLowerCase().contains(query)) {
            results.add(_SearchResult(
              event: event,
              matchType: 'experience',
              matchText: entry.inlineName!,
            ));
          }
        } else {
          // Regular experience
          final exp = widget.experiencesCache[entry.experienceId];
          if (exp != null && exp.name.toLowerCase().contains(query)) {
            results.add(_SearchResult(
              event: event,
              matchType: 'experience',
              matchText: exp.name,
            ));
          }
        }
      }
    }

    setState(() => _searchResults = results);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF2B2930) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search events & experiences...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            // Results
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'Start typing to search events and experiences.'
                            : 'No results found',
                        style: TextStyle(
                          color: widget.isDark
                              ? Colors.white54
                              : Colors.black54,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return _buildSearchResultTile(result);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(_SearchResult result) {
    final dateStr = DateFormat('MMM d, y').format(result.event.startDateTime);
    final timeStr = DateFormat('h:mm a').format(result.event.startDateTime);
    
    String subtitle;
    if (result.matchType == 'event') {
      subtitle = 'Event title • $dateStr at $timeStr';
    } else if (result.matchType == 'description') {
      subtitle = 'Event description • $dateStr';
    } else {
      subtitle = 'Experience • ${result.event.title}';
    }

    return ListTile(
      title: Text(
        result.matchText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        HapticFeedback.heavyImpact();
        widget.onEventSelected(result.event);
      },
      trailing: const Icon(Icons.arrow_forward, size: 18),
    );
  }
}

/// Search result model
class _SearchResult {
  final Event event;
  final String matchType; // 'event', 'description', or 'experience'
  final String matchText;

  _SearchResult({
    required this.event,
    required this.matchType,
    required this.matchText,
  });
}

/// Custom month/year picker sheet
class _MonthYearPickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;

  const _MonthYearPickerSheet({
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  late int _selectedYear;
  late int _selectedMonth;
  bool _isSelectingYear = false;
  late PageController _pageController;
  
  // Year range: current year ± 10 years
  final int _yearRange = 10;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
    
    // Initialize page controller at current year (middle of range)
    _pageController = PageController(initialPage: _yearRange);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with year selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSelectingYear ? 'Select Year' : 'Select Month',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSelectingYear = !_isSelectingYear;
                    });
                  },
                  child: Text(
                    _isSelectingYear 
                        ? 'Done'
                        : '$_selectedYear',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          SizedBox(
            height: 300,
            child: _isSelectingYear
                ? _buildYearSelector(theme, isDark)
                : _buildMonthSelector(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(ThemeData theme, bool isDark) {
    final months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'
    ];

    final currentYear = DateTime.now().year;
    final totalPages = (_yearRange * 2) + 1; // -10 to +10 years = 21 pages

    return Column(
      children: [
        // Swipe hint
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chevron_left,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 8),
              Text(
                'Swipe to change year',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: totalPages,
            onPageChanged: (page) {
              setState(() {
                _selectedYear = currentYear - _yearRange + page;
              });
            },
            itemBuilder: (context, page) {
              final yearForPage = currentYear - _yearRange + page;
              
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  final month = index + 1;
                  final isSelected = month == _selectedMonth && 
                                    yearForPage == _selectedYear;
                  final isCurrentMonth = month == DateTime.now().month && 
                                         yearForPage == DateTime.now().year;

                  return InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      setState(() {
                        _selectedMonth = month;
                        _selectedYear = yearForPage;
                      });
                      widget.onDateSelected(DateTime(yearForPage, month, 1));
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : isCurrentMonth
                                ? theme.colorScheme.primary.withOpacity(0.1)
                                : isDark
                                    ? const Color(0xFF2B2930)
                                    : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        months[index],
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : isCurrentMonth
                                  ? theme.colorScheme.primary
                                  : isDark
                                      ? Colors.white
                                      : Colors.black87,
                          fontWeight: isSelected || isCurrentMonth
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYearSelector(ThemeData theme, bool isDark) {
    final currentYear = DateTime.now().year;
    final years = List.generate(
      20,
      (index) => currentYear - 10 + index,
    );

    return ListView.builder(
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final isSelected = year == _selectedYear;
        final isCurrentYear = year == currentYear;

        return InkWell(
          onTap: () {
            HapticFeedback.heavyImpact();
            setState(() {
              _selectedYear = year;
              _isSelectingYear = false;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            child: Text(
              '$year',
              style: TextStyle(
                color: isSelected || isCurrentYear
                    ? theme.colorScheme.primary
                    : isDark
                        ? Colors.white
                        : Colors.black87,
                fontWeight: isSelected || isCurrentYear
                    ? FontWeight.w600
                    : FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}
