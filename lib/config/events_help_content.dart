import '../models/help_target.dart';
import '../models/events_help_target.dart';

const Map<EventsHelpTargetId, HelpSpec<EventsHelpTargetId>> eventsHelpContent =
    {
  EventsHelpTargetId.helpButton: HelpSpec(
    id: EventsHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Let\'s plan something fun! Tap around and I\'ll show you how your events work.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.monthPicker: HelpSpec(
    id: EventsHelpTargetId.monthPicker,
    steps: [
      HelpStep(
        text: 'Tap the month and year up here to jump to a different date!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.todayButton: HelpSpec(
    id: EventsHelpTargetId.todayButton,
    steps: [
      HelpStep(
        text: 'Lost in the calendar? Tap here to snap right back to today!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.searchButton: HelpSpec(
    id: EventsHelpTargetId.searchButton,
    steps: [
      HelpStep(
        text:
            'Looking for a specific event? Search by title, description, or place name!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.viewTabs: HelpSpec(
    id: EventsHelpTargetId.viewTabs,
    steps: [
      HelpStep(
        text:
            'Pick how you want to see your events -- Day, Week, Month, or Schedule. Each one has its perks!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.dayTabSwitch: HelpSpec(
    id: EventsHelpTargetId.dayTabSwitch,
    steps: [
      HelpStep(
        text:
            'Day view focuses on one day at a time. Swipe left and right to jump between days!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.weekTabSwitch: HelpSpec(
    id: EventsHelpTargetId.weekTabSwitch,
    steps: [
      HelpStep(
        text:
            'Week view lays out your events by day and time so you can see your whole week at a glance!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.monthTabSwitch: HelpSpec(
    id: EventsHelpTargetId.monthTabSwitch,
    steps: [
      HelpStep(
        text:
            'Month view shows the full calendar with little markers for each day that has events.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.scheduleTabSwitch: HelpSpec(
    id: EventsHelpTargetId.scheduleTabSwitch,
    steps: [
      HelpStep(
        text:
            'Schedule view lists all your upcoming events in order. Perfect for a quick scan of what\'s coming up!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.dayView: HelpSpec(
    id: EventsHelpTargetId.dayView,
    steps: [
      HelpStep(
        text:
            'Here\'s your day view! You can see everything planned for this day. Swipe to check other days!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.weekView: HelpSpec(
    id: EventsHelpTargetId.weekView,
    steps: [
      HelpStep(
        text:
            'Your whole week at a glance! Events are laid out by day and time so you can spot openings easily.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.monthView: HelpSpec(
    id: EventsHelpTargetId.monthView,
    steps: [
      HelpStep(
        text:
            'Here\'s the month view! Days with events have little markers so you can see how busy your month is.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.scheduleView: HelpSpec(
    id: EventsHelpTargetId.scheduleView,
    steps: [
      HelpStep(
        text:
            'Your upcoming events, all lined up in order. Scroll through to see what\'s on the horizon!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.addEventButton: HelpSpec(
    id: EventsHelpTargetId.addEventButton,
    steps: [
      HelpStep(
        text: 'Ready to plan something? Tap the + to start a brand new event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.monthCalendar: HelpSpec(
    id: EventsHelpTargetId.monthCalendar,
    steps: [
      HelpStep(
        text:
            'This calendar helps you pick a day and see which ones have events. Tap a day to check it out!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.monthEventCard: HelpSpec(
    id: EventsHelpTargetId.monthEventCard,
    steps: [
      HelpStep(
        text:
            'Here\'s an event card! It shows the key details for this day. Tap it to open the full event editor.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.dayPreviousButton: HelpSpec(
    id: EventsHelpTargetId.dayPreviousButton,
    steps: [
      HelpStep(
        text: 'Go back to the previous day.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.dayNextButton: HelpSpec(
    id: EventsHelpTargetId.dayNextButton,
    steps: [
      HelpStep(
        text: 'Jump ahead to the next day.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.dayEventCard: HelpSpec(
    id: EventsHelpTargetId.dayEventCard,
    steps: [
      HelpStep(
        text:
            'Here\'s an event for this day! Tap to open it up and see all the details.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.weekEventCard: HelpSpec(
    id: EventsHelpTargetId.weekEventCard,
    steps: [
      HelpStep(
        text:
            'This block represents an event, sized by how long it lasts. Tap it for more details!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventsHelpTargetId.scheduleEventCard: HelpSpec(
    id: EventsHelpTargetId.scheduleEventCard,
    steps: [
      HelpStep(
        text:
            'Here\'s an upcoming event in your schedule. Tap it to see the full details!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
