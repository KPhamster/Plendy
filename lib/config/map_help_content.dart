import '../models/help_target.dart';
import '../models/map_help_target.dart';

const Map<MapHelpTargetId, HelpSpec<MapHelpTargetId>> mapHelpContent = {
  // ───────────────────── Common ─────────────────────

  MapHelpTargetId.helpButton: HelpSpec(
    id: MapHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Let\'s explore the map together! Tap on anything and I\'ll walk you through it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.calendarToggle: HelpSpec(
    id: MapHelpTargetId.calendarToggle,
    steps: [
      HelpStep(
        text:
            'Tap here to pull up the calendar and see your upcoming events on the map!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Events group your experiences into planned outings with dates and itineraries. Super handy for trip planning!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.globeToggle: HelpSpec(
    id: MapHelpTargetId.globeToggle,
    steps: [
      HelpStep(
        text:
            'Go global or stay local! Toggle this to see all your experiences worldwide or just the ones nearby.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.filterButton: HelpSpec(
    id: MapHelpTargetId.filterButton,
    steps: [
      HelpStep(
        text:
            'Too many pins? Use filters to narrow down by category, color, or whatever you need!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.searchBar: HelpSpec(
    id: MapHelpTargetId.searchBar,
    steps: [
      HelpStep(
        text:
            'Need to find a spot? Search by name, address, or even your saved places!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.clearSearch: HelpSpec(
    id: MapHelpTargetId.clearSearch,
    steps: [
      HelpStep(
        text: 'Tap here to clear your search and see the full map again!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.mapArea: HelpSpec(
    id: MapHelpTargetId.mapArea,
    steps: [
      HelpStep(
        text:
            'Here\'s your personal map! Every pin is a place you\'ve saved.',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Tap any pin to see its details. Pinch to zoom in, and drag to move around!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ───────────── Events dialog ───────────────────

  MapHelpTargetId.eventsDialogHelpButton: HelpSpec(
    id: MapHelpTargetId.eventsDialogHelpButton,
    steps: [
      HelpStep(
        text:
            'I\'m here to help with this dialog! Tap any button or event card to learn what it does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventsDialogCreateNew: HelpSpec(
    id: MapHelpTargetId.eventsDialogCreateNew,
    steps: [
      HelpStep(
        text:
            'Start a brand-new event by picking experiences right from the map! Just tap the pins you want.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventsDialogClose: HelpSpec(
    id: MapHelpTargetId.eventsDialogClose,
    steps: [
      HelpStep(
        text: 'Close this dialog and head back to the map.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventsDialogEventCard: HelpSpec(
    id: MapHelpTargetId.eventsDialogEventCard,
    steps: [
      HelpStep(
        text:
            'Tap an event card to see its options! You can jump into view mode or start editing.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ───────── Event options sheet ────────────────

  MapHelpTargetId.eventOptionsHelpButton: HelpSpec(
    id: MapHelpTargetId.eventOptionsHelpButton,
    steps: [
      HelpStep(
        text:
            'Here are your event options! Tap any action to learn what it does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventOptionsViewPage: HelpSpec(
    id: MapHelpTargetId.eventOptionsViewPage,
    steps: [
      HelpStep(
        text:
            'Open the full event page to see all the details and make edits!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventOptionsViewMap: HelpSpec(
    id: MapHelpTargetId.eventOptionsViewMap,
    steps: [
      HelpStep(
        text:
            'See this event\'s itinerary laid out on the map! Great for visualizing your route.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ───────────── Event view mode ─────────────────

  MapHelpTargetId.eventViewHeader: HelpSpec(
    id: MapHelpTargetId.eventViewHeader,
    steps: [
      HelpStep(
        text:
            'This shows your event itinerary on the map. Tap here to fit all the stops into view!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventViewListToggle: HelpSpec(
    id: MapHelpTargetId.eventViewListToggle,
    steps: [
      HelpStep(
        text: 'Show or hide the list of itinerary stops for this event.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.eventViewAddExperiences: HelpSpec(
    id: MapHelpTargetId.eventViewAddExperiences,
    steps: [
      HelpStep(
        text:
            'Want to add more stops? Tap pins on the map to include them in your event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ───────────── Select mode ─────────────────────

  MapHelpTargetId.selectModeListToggle: HelpSpec(
    id: MapHelpTargetId.selectModeListToggle,
    steps: [
      HelpStep(
        text:
            'Show or hide the list of experiences you\'ve picked so far.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.selectModeFinish: HelpSpec(
    id: MapHelpTargetId.selectModeFinish,
    steps: [
      HelpStep(
        text:
            'All done picking? Tap here to open the event editor with your selected experiences!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.selectModeClose: HelpSpec(
    id: MapHelpTargetId.selectModeClose,
    steps: [
      HelpStep(
        text: 'Changed your mind? Tap here to exit selection mode and go back to the normal map.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ──────── Location details panel ───────────────

  MapHelpTargetId.detailsPanel: HelpSpec(
    id: MapHelpTargetId.detailsPanel,
    steps: [
      HelpStep(
        text:
            'Here are the details for this spot! I\'ll show you what you\'ve saved here.',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Tap here to open the full experience page with all your saved content and info!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsShare: HelpSpec(
    id: MapHelpTargetId.detailsShare,
    steps: [
      HelpStep(
        text: 'Share this experience with other Plendy users!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsGoogleMaps: HelpSpec(
    id: MapHelpTargetId.detailsGoogleMaps,
    steps: [
      HelpStep(
        text:
            'Open this spot in Google Maps for more details, reviews, and photos!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsDirections: HelpSpec(
    id: MapHelpTargetId.detailsDirections,
    steps: [
      HelpStep(
        text: 'Need directions? Tap here to get driving or walking directions to this spot!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsClose: HelpSpec(
    id: MapHelpTargetId.detailsClose,
    steps: [
      HelpStep(
        text: 'Close this panel and deselect the location.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsPlayContent: HelpSpec(
    id: MapHelpTargetId.detailsPlayContent,
    steps: [
      HelpStep(
        text:
            'Want a quick peek? Preview the content saved here without leaving the map!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsAddToEvent: HelpSpec(
    id: MapHelpTargetId.detailsAddToEvent,
    steps: [
      HelpStep(
        text: 'Add this spot to your event itinerary!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  MapHelpTargetId.detailsRemoveFromEvent: HelpSpec(
    id: MapHelpTargetId.detailsRemoveFromEvent,
    steps: [
      HelpStep(
        text: 'Remove this spot from the event itinerary.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
