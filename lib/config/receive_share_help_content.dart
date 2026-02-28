import '../models/help_target.dart';
import '../models/receive_share_help_target.dart';

const Map<ReceiveShareHelpTargetId, HelpSpec<ReceiveShareHelpTargetId>>
    receiveShareHelpContent = {
  // ─── Main screen – common ───────────────────────────────

  ReceiveShareHelpTargetId.helpButton: HelpSpec(
    id: ReceiveShareHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Nice, you\'re saving something new! Let me walk you through how it works. Tap on anything to learn more!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.privacyToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.privacyToggle,
    steps: [
      HelpStep(
        text:
            'This controls privacy for everything you\'re saving. Public content shows up in Discovery for others to find!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Each experience card can also have its own privacy setting if you want to mix and match.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.privacyTooltip: HelpSpec(
    id: ReceiveShareHelpTargetId.privacyTooltip,
    steps: [
      HelpStep(
        text:
            'Not sure about public vs. private? Tap this icon for a quick explanation!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── URL input area ─────────────────────────────────────

  ReceiveShareHelpTargetId.urlInputField: HelpSpec(
    id: ReceiveShareHelpTargetId.urlInputField,
    steps: [
      HelpStep(
        text:
            'Paste or type a URL here to save content from the web or social media!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'I work with Instagram, TikTok, YouTube, Yelp, Facebook, and tons more!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.urlClearButton: HelpSpec(
    id: ReceiveShareHelpTargetId.urlClearButton,
    steps: [
      HelpStep(
        text: 'Clear the URL and start fresh!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.urlPasteButton: HelpSpec(
    id: ReceiveShareHelpTargetId.urlPasteButton,
    steps: [
      HelpStep(
        text: 'Paste a URL straight from your clipboard -- quick and easy!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.urlSubmitButton: HelpSpec(
    id: ReceiveShareHelpTargetId.urlSubmitButton,
    steps: [
      HelpStep(
        text: 'Hit this to load the URL and start saving!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.screenshotUploadButton: HelpSpec(
    id: ReceiveShareHelpTargetId.screenshotUploadButton,
    steps: [
      HelpStep(
        text:
            'Got a screenshot? Upload it and I\'ll use AI to pull out locations and details from the image!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.scanButton: HelpSpec(
    id: ReceiveShareHelpTargetId.scanButton,
    steps: [
      HelpStep(
        text:
            'Let me work my magic! I\'ll scan this content and pull out any locations, categories, or event details I can find.',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'A quick scan grabs the main location. A deep scan finds every location mentioned!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Media preview section ──────────────────────────────

  ReceiveShareHelpTargetId.mediaPreviewSection: HelpSpec(
    id: ReceiveShareHelpTargetId.mediaPreviewSection,
    steps: [
      HelpStep(
        text:
            'Here\'s a live preview of what you\'re saving! Scroll around to explore it.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Experience cards section ───────────────────────────

  ReceiveShareHelpTargetId.experienceCardsSection: HelpSpec(
    id: ReceiveShareHelpTargetId.experienceCardsSection,
    steps: [
      HelpStep(
        text:
            'Each card is an experience you\'ll save. Just fill in the location and pick a category!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Expand a card to see all the fields. You can even save multiple experiences from one link!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.addAnotherExperienceButton: HelpSpec(
    id: ReceiveShareHelpTargetId.addAnotherExperienceButton,
    steps: [
      HelpStep(
        text:
            'Want to save this to another place too? Add another card with a different location or category!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Bottom action row ──────────────────────────────────

  ReceiveShareHelpTargetId.cancelButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cancelButton,
    steps: [
      HelpStep(
        text: 'Changed your mind? This discards everything and takes you back.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.quickAddButton: HelpSpec(
    id: ReceiveShareHelpTargetId.quickAddButton,
    steps: [
      HelpStep(
        text:
            'Know exactly where this belongs? Quick Add lets you search for a place or pick from your saved experiences!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'It\'s the fastest way to save when you already have the spot in mind.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.saveButton: HelpSpec(
    id: ReceiveShareHelpTargetId.saveButton,
    steps: [
      HelpStep(
        text:
            'All set? Tap here to save! Just make sure each card has a location and category first.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Scroll FAB ─────────────────────────────────────────

  ReceiveShareHelpTargetId.scrollFab: HelpSpec(
    id: ReceiveShareHelpTargetId.scrollFab,
    steps: [
      HelpStep(
        text:
            'Jump between the media preview and the experience cards. Handy when the page gets long!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── ExperienceCardForm internals ───────────────────────

  ReceiveShareHelpTargetId.cardHeader: HelpSpec(
    id: ReceiveShareHelpTargetId.cardHeader,
    steps: [
      HelpStep(
        text: 'Tap to expand or collapse this experience card!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardRemoveButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardRemoveButton,
    steps: [
      HelpStep(
        text:
            'Remove this card. Don\'t worry, you always need at least one!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardPrivacyToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.cardPrivacyToggle,
    steps: [
      HelpStep(
        text:
            'Override the global privacy just for this card. Handy if you want some public and some private!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardEventSelector: HelpSpec(
    id: ReceiveShareHelpTargetId.cardEventSelector,
    steps: [
      HelpStep(
        text:
            'Link this to an event! It\'ll show up in that event\'s itinerary.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardSavedExperienceChooser: HelpSpec(
    id: ReceiveShareHelpTargetId.cardSavedExperienceChooser,
    steps: [
      HelpStep(
        text:
            'Already have this place saved? Attach the content to your existing experience instead of making a new one!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardLocationArea: HelpSpec(
    id: ReceiveShareHelpTargetId.cardLocationArea,
    steps: [
      HelpStep(
        text:
            'This is the location for the experience. Tap the map icon to search for a place!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardLocationToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.cardLocationToggle,
    steps: [
      HelpStep(
        text:
            'Turn location on or off for this card. Off means it won\'t have a pin on the map.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardLocationPickerButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardLocationPickerButton,
    steps: [
      HelpStep(
        text:
            'Open the location picker to search for a place or browse the map!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardGoogleMapsButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardGoogleMapsButton,
    steps: [
      HelpStep(
        text:
            'Check this spot on Google Maps for reviews and directions!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardYelpButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardYelpButton,
    steps: [
      HelpStep(
        text: 'Look this place up on Yelp to compare ratings and reviews!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardTitleField: HelpSpec(
    id: ReceiveShareHelpTargetId.cardTitleField,
    steps: [
      HelpStep(
        text:
            'The title for this experience! It\'s auto-filled when possible, but you can change it.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardCategoryButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardCategoryButton,
    steps: [
      HelpStep(
        text:
            'Pick a category to organize this experience in your collections!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardColorCategoryButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardColorCategoryButton,
    steps: [
      HelpStep(
        text:
            'Choose a color category to visually tag this experience on the map!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardAssignMoreCategoriesButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardAssignMoreCategoriesButton,
    steps: [
      HelpStep(
        text:
            'Add extra categories so this experience shows up in more than one collection!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardOtherCategoriesButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardOtherCategoriesButton,
    steps: [
      HelpStep(
        text:
            'Add more color categories so this experience appears under multiple color filters!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardWebsiteField: HelpSpec(
    id: ReceiveShareHelpTargetId.cardWebsiteField,
    steps: [
      HelpStep(
        text:
            'A reference URL for the experience. It\'s auto-filled from the shared link!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardWebsitePasteButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardWebsitePasteButton,
    steps: [
      HelpStep(
        text: 'Paste a website URL from your clipboard!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardWebsiteLaunchButton: HelpSpec(
    id: ReceiveShareHelpTargetId.cardWebsiteLaunchButton,
    steps: [
      HelpStep(
        text: 'Open the website in your browser to check it out!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.cardNotesField: HelpSpec(
    id: ReceiveShareHelpTargetId.cardNotesField,
    steps: [
      HelpStep(
        text:
            'Jot down some personal notes or reminders about this experience!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Preview widget controls ────────────────────────────

  ReceiveShareHelpTargetId.previewDisplayModeToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.previewDisplayModeToggle,
    steps: [
      HelpStep(
        text:
            'Switch between Default view and Web view for the preview. Try both and see which you prefer!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.previewRefreshButton: HelpSpec(
    id: ReceiveShareHelpTargetId.previewRefreshButton,
    steps: [
      HelpStep(
        text: 'Preview not loading right? Give it a refresh!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.previewOpenExternalButton: HelpSpec(
    id: ReceiveShareHelpTargetId.previewOpenExternalButton,
    steps: [
      HelpStep(
        text: 'Open this link in your browser or the native app!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.previewExpandButton: HelpSpec(
    id: ReceiveShareHelpTargetId.previewExpandButton,
    steps: [
      HelpStep(
        text: 'Expand or collapse the preview to see more or less of the content!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.previewLinkRow: HelpSpec(
    id: ReceiveShareHelpTargetId.previewLinkRow,
    steps: [
      HelpStep(
        text: 'Tap the URL to open it in your browser!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── QuickAdd dialog ────────────────────────────────────

  ReceiveShareHelpTargetId.quickAddSearchField: HelpSpec(
    id: ReceiveShareHelpTargetId.quickAddSearchField,
    steps: [
      HelpStep(
        text:
            'Search for a place by name or address! Results come from Google Maps and your saved experiences.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.quickAddSavedExperienceToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.quickAddSavedExperienceToggle,
    steps: [
      HelpStep(
        text:
            'Switch between searching for new places or picking from ones you\'ve already saved!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.quickAddResultRow: HelpSpec(
    id: ReceiveShareHelpTargetId.quickAddResultRow,
    steps: [
      HelpStep(
        text: 'Tap a result to use it as the location!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.quickAddConfirmButton: HelpSpec(
    id: ReceiveShareHelpTargetId.quickAddConfirmButton,
    steps: [
      HelpStep(
        text: 'All good? Confirm your pick and save the content!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── MultiLocation dialog ───────────────────────────────

  ReceiveShareHelpTargetId.multiLocationCheckbox: HelpSpec(
    id: ReceiveShareHelpTargetId.multiLocationCheckbox,
    steps: [
      HelpStep(
        text:
            'I found some locations! Check the ones you want and each will become its own experience card.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.multiLocationDeepScanButton: HelpSpec(
    id: ReceiveShareHelpTargetId.multiLocationDeepScanButton,
    steps: [
      HelpStep(
        text:
            'Want me to dig deeper? A deep scan looks for even more locations mentioned in the content!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.multiLocationCancelButton: HelpSpec(
    id: ReceiveShareHelpTargetId.multiLocationCancelButton,
    steps: [
      HelpStep(
        text: 'Close this without applying any changes.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.multiLocationConfirmButton: HelpSpec(
    id: ReceiveShareHelpTargetId.multiLocationConfirmButton,
    steps: [
      HelpStep(
        text:
            'Looks good! Confirm to create experience cards for all the checked locations.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.multiLocationScannedTextToggle: HelpSpec(
    id: ReceiveShareHelpTargetId.multiLocationScannedTextToggle,
    steps: [
      HelpStep(
        text:
            'Curious what the AI actually read? Expand this to see the raw scanned text!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Select Event dialog ────────────────────────────────

  ReceiveShareHelpTargetId.selectEventRow: HelpSpec(
    id: ReceiveShareHelpTargetId.selectEventRow,
    steps: [
      HelpStep(
        text: 'Tap an event to link this experience to it!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.selectEventConfirmButton: HelpSpec(
    id: ReceiveShareHelpTargetId.selectEventConfirmButton,
    steps: [
      HelpStep(
        text: 'Confirm and attach the experience to your selected event!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ─── Category / Color selection dialogs ─────────────────

  ReceiveShareHelpTargetId.categorySearchField: HelpSpec(
    id: ReceiveShareHelpTargetId.categorySearchField,
    steps: [
      HelpStep(
        text: 'Type to filter and find the category you\'re looking for!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.categoryRow: HelpSpec(
    id: ReceiveShareHelpTargetId.categoryRow,
    steps: [
      HelpStep(
        text: 'Tap a category to pick it for this experience!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.categoryAddButton: HelpSpec(
    id: ReceiveShareHelpTargetId.categoryAddButton,
    steps: [
      HelpStep(
        text: 'None of these fit? Create a brand new category!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.categoryEditButton: HelpSpec(
    id: ReceiveShareHelpTargetId.categoryEditButton,
    steps: [
      HelpStep(
        text: 'Rename or delete your existing categories from here.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.colorCategoryRow: HelpSpec(
    id: ReceiveShareHelpTargetId.colorCategoryRow,
    steps: [
      HelpStep(
        text: 'Tap a color category to assign it to this experience!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.colorCategoryAddButton: HelpSpec(
    id: ReceiveShareHelpTargetId.colorCategoryAddButton,
    steps: [
      HelpStep(
        text: 'Create a new color category with your own custom color!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.colorCategoryEditButton: HelpSpec(
    id: ReceiveShareHelpTargetId.colorCategoryEditButton,
    steps: [
      HelpStep(
        text: 'Edit or remove your existing color categories.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.otherCategoriesCheckbox: HelpSpec(
    id: ReceiveShareHelpTargetId.otherCategoriesCheckbox,
    steps: [
      HelpStep(
        text:
            'Check extra color categories to tag this experience with more than one!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  ReceiveShareHelpTargetId.otherCategoriesConfirmButton: HelpSpec(
    id: ReceiveShareHelpTargetId.otherCategoriesConfirmButton,
    steps: [
      HelpStep(
        text: 'All done? Confirm your color category picks!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),
};
