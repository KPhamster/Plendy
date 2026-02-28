import '../models/event_editor_help_target.dart';
import '../models/help_target.dart';

const Map<EventEditorHelpTargetId, HelpSpec<EventEditorHelpTargetId>>
    eventEditorHelpContent = {
  EventEditorHelpTargetId.helpButton: HelpSpec(
    id: EventEditorHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Let me walk you through the event editor! Tap on anything to learn what it does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.backButton: HelpSpec(
    id: EventEditorHelpTargetId.backButton,
    steps: [
      HelpStep(
        text: 'Head back to the previous screen.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.viewMode: HelpSpec(
    id: EventEditorHelpTargetId.viewMode,
    steps: [
      HelpStep(
        text:
            'You\'re in view mode right now -- everything\'s read-only. Switch to edit mode to make changes!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.editMode: HelpSpec(
    id: EventEditorHelpTargetId.editMode,
    steps: [
      HelpStep(
        text:
            'You\'re in edit mode! Make your changes and don\'t forget to save when you\'re done.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.signInButton: HelpSpec(
    id: EventEditorHelpTargetId.signInButton,
    steps: [
      HelpStep(
        text:
            'Sign in to get editing access if you have permission for this event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.editButton: HelpSpec(
    id: EventEditorHelpTargetId.editButton,
    steps: [
      HelpStep(
        text: 'Tap here to switch into edit mode and start making changes!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.saveButton: HelpSpec(
    id: EventEditorHelpTargetId.saveButton,
    steps: [
      HelpStep(
        text: 'Happy with your changes? Tap here to save everything!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.coverImage: HelpSpec(
    id: EventEditorHelpTargetId.coverImage,
    steps: [
      HelpStep(
        text: 'Add or change the cover image for your event! First impressions matter.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleMapButton: HelpSpec(
    id: EventEditorHelpTargetId.scheduleMapButton,
    steps: [
      HelpStep(
        text: 'See this event on the map! Great for visualizing where everything is.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleTicketmasterButton: HelpSpec(
    id: EventEditorHelpTargetId.scheduleTicketmasterButton,
    steps: [
      HelpStep(
        text: 'Check Ticketmaster for tickets related to this event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleShareButton: HelpSpec(
    id: EventEditorHelpTargetId.scheduleShareButton,
    steps: [
      HelpStep(
        text: 'Share this event with friends so they can join in!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleColorButton: HelpSpec(
    id: EventEditorHelpTargetId.scheduleColorButton,
    steps: [
      HelpStep(
        text: 'Pick a custom color for your event so it stands out on the calendar!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleStartDate: HelpSpec(
    id: EventEditorHelpTargetId.scheduleStartDate,
    steps: [
      HelpStep(
        text: 'When does the fun begin? Set your start date and time here!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.scheduleEndDate: HelpSpec(
    id: EventEditorHelpTargetId.scheduleEndDate,
    steps: [
      HelpStep(
        text: 'And when does it wrap up? Set the end date and time!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itinerarySection: HelpSpec(
    id: EventEditorHelpTargetId.itinerarySection,
    steps: [
      HelpStep(
        text:
            'Here\'s your itinerary! These are all the stops planned for this event.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryAddEventOnlyQuick: HelpSpec(
    id: EventEditorHelpTargetId.itineraryAddEventOnlyQuick,
    steps: [
      HelpStep(
        text: 'Quickly add a new stop that\'s just for this event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryAddSavedQuick: HelpSpec(
    id: EventEditorHelpTargetId.itineraryAddSavedQuick,
    steps: [
      HelpStep(
        text: 'Add a stop from your saved experiences. Piece of cake!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryCard: HelpSpec(
    id: EventEditorHelpTargetId.itineraryCard,
    steps: [
      HelpStep(
        text: 'Tap to expand this stop and see all the actions you can take!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryCardMap: HelpSpec(
    id: EventEditorHelpTargetId.itineraryCardMap,
    steps: [
      HelpStep(
        text: 'See this stop on the map!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryCardDirections: HelpSpec(
    id: EventEditorHelpTargetId.itineraryCardDirections,
    steps: [
      HelpStep(
        text: 'Get turn-by-turn directions to this stop!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryCardContent: HelpSpec(
    id: EventEditorHelpTargetId.itineraryCardContent,
    steps: [
      HelpStep(
        text: 'Preview the media and content attached to this stop!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemScheduledTime: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemScheduledTime,
    steps: [
      HelpStep(
        text: 'Check or set the scheduled time for this stop!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemTransport: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemTransport,
    steps: [
      HelpStep(
        text:
            'Add transportation notes -- how are you getting to this stop?',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemNotes: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemNotes,
    steps: [
      HelpStep(
        text: 'Jot down notes for this stop -- reminders, tips, anything!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemOpen: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemOpen,
    steps: [
      HelpStep(
        text: 'Open the full experience page for this stop!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemEdit: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemEdit,
    steps: [
      HelpStep(
        text: 'Edit the details for this event-only stop.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryItemRemove: HelpSpec(
    id: EventEditorHelpTargetId.itineraryItemRemove,
    steps: [
      HelpStep(
        text: 'Remove this stop from the itinerary.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryAddEventOnly: HelpSpec(
    id: EventEditorHelpTargetId.itineraryAddEventOnly,
    steps: [
      HelpStep(
        text: 'Add a new stop that\'s just for this event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.itineraryAddSaved: HelpSpec(
    id: EventEditorHelpTargetId.itineraryAddSaved,
    steps: [
      HelpStep(
        text: 'Add stops from your saved experiences to the itinerary!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.peopleSection: HelpSpec(
    id: EventEditorHelpTargetId.peopleSection,
    steps: [
      HelpStep(
        text:
            'Here\'s the people section! See who\'s planning, collaborating, and viewing this event.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.peopleToggle: HelpSpec(
    id: EventEditorHelpTargetId.peopleToggle,
    steps: [
      HelpStep(
        text: 'Show or hide the full people list.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.peopleManageMember: HelpSpec(
    id: EventEditorHelpTargetId.peopleManageMember,
    steps: [
      HelpStep(
        text:
            'Manage this person\'s role -- you can remove collaborators or viewers from here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.peopleAddCollaborators: HelpSpec(
    id: EventEditorHelpTargetId.peopleAddCollaborators,
    steps: [
      HelpStep(
        text:
            'Invite people as collaborators! They\'ll be able to edit the event.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.peopleAddViewers: HelpSpec(
    id: EventEditorHelpTargetId.peopleAddViewers,
    steps: [
      HelpStep(
        text:
            'Invite people as viewers! They can see everything but can\'t make changes.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.visibilitySection: HelpSpec(
    id: EventEditorHelpTargetId.visibilitySection,
    steps: [
      HelpStep(
        text:
            'This is where you control who can see and access your event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.visibilityOptions: HelpSpec(
    id: EventEditorHelpTargetId.visibilityOptions,
    steps: [
      HelpStep(
        text: 'Choose who can discover and access this event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.visibilityGenerateLink: HelpSpec(
    id: EventEditorHelpTargetId.visibilityGenerateLink,
    steps: [
      HelpStep(
        text: 'Generate a fresh share link so people can join your event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.visibilityCopyLink: HelpSpec(
    id: EventEditorHelpTargetId.visibilityCopyLink,
    steps: [
      HelpStep(
        text: 'Copy the share link to your clipboard -- ready to paste anywhere!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.visibilityRevokeLink: HelpSpec(
    id: EventEditorHelpTargetId.visibilityRevokeLink,
    steps: [
      HelpStep(
        text: 'Disable the current share link so it can\'t be used anymore.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.capacityField: HelpSpec(
    id: EventEditorHelpTargetId.capacityField,
    steps: [
      HelpStep(
        text: 'Set a max number of attendees if you need to limit the group size!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.notificationsDropdown: HelpSpec(
    id: EventEditorHelpTargetId.notificationsDropdown,
    steps: [
      HelpStep(
        text: 'Pick when attendees should get a reminder about the event!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.descriptionField: HelpSpec(
    id: EventEditorHelpTargetId.descriptionField,
    steps: [
      HelpStep(
        text: 'Add a description so everyone knows what the event is about!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.commentInput: HelpSpec(
    id: EventEditorHelpTargetId.commentInput,
    steps: [
      HelpStep(
        text: 'Type a comment for the event attendees here!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.commentSend: HelpSpec(
    id: EventEditorHelpTargetId.commentSend,
    steps: [
      HelpStep(
        text: 'Post your comment for everyone to see!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EventEditorHelpTargetId.deleteButton: HelpSpec(
    id: EventEditorHelpTargetId.deleteButton,
    steps: [
      HelpStep(
        text:
            'Careful! This permanently deletes the entire event. There\'s no going back!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
