import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/event.dart';
import '../models/experience.dart';
import '../services/event_service.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/event_editor_modal.dart';

/// Google Calendar-style events screen with Material 3 Expressive design
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  final _eventService = EventService();
  final _authService = AuthService();

  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // View mode: 'day', 'week', 'month', 'schedule'
  String _viewMode = 'month';

  // Events data
  List<Event> _allEvents = [];
  Map<DateTime, List<Event>> _eventsByDate = {};
  bool _isLoading = true;

  late TabController _tabController;
  late PageController _weekPageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 2);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
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
              break;
          }
        });
      }
    });
    // Initialize week page controller at "current week" (middle of range)
    _weekPageController = PageController(initialPage: 52); // ~1 year range
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _weekPageController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final userId = _authService.currentUser?.uid;
      debugPrint('EventsScreen: Loading events for user: $userId');
      
      if (userId != null) {
        final events = await _eventService.getEventsForUser(userId);
        debugPrint('EventsScreen: Loaded ${events.length} events');
        
        for (final event in events) {
          debugPrint('Event: ${event.title} - ${event.startDateTime}');
        }
        
        setState(() {
          _allEvents = events;
          _eventsByDate = _groupEventsByDate(events);
          _isLoading = false;
        });
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

      final result = await Navigator.push(
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

      if (result != null) {
        _loadEvents();
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1B1F) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(theme, isDark),
            _buildViewTabs(theme, isDark),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildViewContent(theme, isDark),
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
              onTap: () => _showMonthPicker(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      DateFormat('MMMM y').format(_focusedDay),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Google Sans',
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
            onPressed: _goToToday,
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
            onPressed: () {
              // TODO: Implement search
            },
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
                    DateFormat('EEEE, MMMM d').format(_selectedDay),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
    return Container(
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
        onTap: () => _openEventDetails(event),
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
    // Group events by date
    final now = DateTime.now();
    final upcomingEvents = _allEvents.where((event) {
      return event.startDateTime.isAfter(now.subtract(const Duration(days: 1)));
    }).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    if (upcomingEvents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
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

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: upcomingEvents.length,
      itemBuilder: (context, index) {
        final event = upcomingEvents[index];
        final showDateHeader = index == 0 ||
            !isSameDay(
              event.startDateTime,
              upcomingEvents[index - 1].startDateTime,
            );

        return Column(
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
            _buildEventCard(event, theme, isDark),
          ],
        );
      },
      ),
    );
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

  Widget _buildEventCard(Event event, ThemeData theme, bool isDark) {
    final cardColor = isDark
        ? const Color(0xFF2B2930)
        : Colors.white;
    final borderColor = _getEventColor(event);

    return GestureDetector(
      onTap: () => _openEventDetails(event),
      child: Container(
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
                      // Experience count
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
                              '${event.experiences.length} location${event.experiences.length != 1 ? 's' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
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
      final experienceIds = event.experiences
          .map((entry) => entry.experienceId)
          .toList();
      
      final experienceService = ExperienceService();
      
      List<Experience> experiences = [];
      if (experienceIds.isNotEmpty) {
        experiences = await experienceService.getExperiencesByIds(experienceIds);
      }

      // Fetch user's categories and color categories
      final categories = await experienceService.getUserCategories();
      final colorCategories = await experienceService.getUserColorCategories();
      
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EventEditorModal(
            event: event,
            experiences: experiences,
            categories: categories,
            colorCategories: colorCategories,
          ),
          fullscreenDialog: true,
        ),
      );

      if (result != null) {
        _loadEvents();
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
    // Generate a color based on event ID for consistency
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
        },
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
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
