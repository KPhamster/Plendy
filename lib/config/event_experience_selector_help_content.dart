import '../models/event_experience_selector_help_target.dart';
import '../models/help_target.dart';

const Map<EventExperienceSelectorHelpTargetId,
        HelpSpec<EventExperienceSelectorHelpTargetId>>
    eventExperienceSelectorHelpContent = {
  EventExperienceSelectorHelpTargetId.helpButton: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Let\'s pick some experiences for your event! Tap around and I\'ll show you how.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.categoriesTabSwitch: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.categoriesTabSwitch,
    steps: [
      HelpStep(
        text:
            'Browse by Categories! This groups your experiences by collection so it\'s easier to find what you want.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.experiencesTabSwitch: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.experiencesTabSwitch,
    steps: [
      HelpStep(
        text:
            'Or browse all your Experiences directly! Pick specific places to add to your event.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.currentView: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.currentView,
    steps: [
      HelpStep(
        text: 'This is where your selection options are showing! Browse and pick what you need.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.searchBar: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.searchBar,
    steps: [
      HelpStep(
        text: 'Looking for something specific? Search by name to find it fast!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.filterButton: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.filterButton,
    steps: [
      HelpStep(
        text: 'Filter by categories or colors to narrow things down!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventExperienceSelectorHelpTargetId.doneButton: HelpSpec(
    id: EventExperienceSelectorHelpTargetId.doneButton,
    steps: [
      HelpStep(
        text: 'All done picking? Tap here to save your selection and head back!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
