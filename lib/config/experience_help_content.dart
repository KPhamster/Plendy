import '../models/help_target.dart';
import '../models/experience_help_target.dart';

const Map<ExperienceHelpTargetId, HelpSpec<ExperienceHelpTargetId>>
    experienceHelpContent = {
  ExperienceHelpTargetId.helpButton: HelpSpec(
    id: ExperienceHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Here\'s everything about this place! Tap on any part and I\'ll fill you in.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.backButton: HelpSpec(
    id: ExperienceHelpTargetId.backButton,
    steps: [
      HelpStep(
        text: 'Tap here to head back to where you came from.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.overflowMenu: HelpSpec(
    id: ExperienceHelpTargetId.overflowMenu,
    steps: [
      HelpStep(
        text:
            'More options here! You can report this experience or remove it from your collection.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.saveExperienceButton: HelpSpec(
    id: ExperienceHelpTargetId.saveExperienceButton,
    steps: [
      HelpStep(
        text:
            'Like what you see? Save this shared experience to your own collection so it\'s always there when you need it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.heroRatingButtons: HelpSpec(
    id: ExperienceHelpTargetId.heroRatingButtons,
    steps: [
      HelpStep(
        text:
            'What do you think of this place? Give it a thumbs up or down -- other people can see your vote too!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsActionMapScreen: HelpSpec(
    id: ExperienceHelpTargetId.detailsActionMapScreen,
    steps: [
      HelpStep(
        text:
            'See this place on the map! It\'ll zoom right to the location so you can check out what\'s nearby.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsActionShareExperience: HelpSpec(
    id: ExperienceHelpTargetId.detailsActionShareExperience,
    steps: [
      HelpStep(
        text:
            'Share this experience with friends or send them a link!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsActionCreateEvent: HelpSpec(
    id: ExperienceHelpTargetId.detailsActionCreateEvent,
    steps: [
      HelpStep(
        text:
            'Want to plan a visit? Create a new event and this place will be the first stop on your itinerary!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsActionEditExperience: HelpSpec(
    id: ExperienceHelpTargetId.detailsActionEditExperience,
    steps: [
      HelpStep(
        text:
            'Edit this experience! You can change the name, category, location, and all the details.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsLocationRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsLocationRow,
    steps: [
      HelpStep(
        text:
            'Tap the address to open it in your maps app for directions or a closer look!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsCategoryRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsCategoryRow,
    steps: [
      HelpStep(
        text:
            'This is the main category for this experience. It helps you quickly see how it\'s organized in your collection!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsColorCategoryRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsColorCategoryRow,
    steps: [
      HelpStep(
        text:
            'Here\'s the color category label! If you have edit access, tap it to change the color.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsDescriptionIcon: HelpSpec(
    id: ExperienceHelpTargetId.detailsDescriptionIcon,
    steps: [
      HelpStep(
        text: 'This marks the description section for the venue.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsDescriptionText: HelpSpec(
    id: ExperienceHelpTargetId.detailsDescriptionText,
    steps: [
      HelpStep(
        text:
            'Here\'s a quick summary of the place! It\'s pulled from your saved details or Google data.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsStatusRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsStatusRow,
    steps: [
      HelpStep(
        text:
            'This tells you if the place is open or closed right now based on the latest hours data!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsHoursRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsHoursRow,
    steps: [
      HelpStep(
        text:
            'Today\'s hours are right here! Tap to expand and see the full weekly schedule.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsReservationsRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsReservationsRow,
    steps: [
      HelpStep(
        text:
            'Good to know -- this shows whether the place takes reservations when that info is available!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsParkingRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsParkingRow,
    steps: [
      HelpStep(
        text:
            'Parking info! This shows options like lot, garage, street, or valet when known.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.detailsOtherCategoriesRow: HelpSpec(
    id: ExperienceHelpTargetId.detailsOtherCategoriesRow,
    steps: [
      HelpStep(
        text:
            'This experience has extra categories and color tags! These help it show up in multiple places in your collection.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.quickActionCallVenue: HelpSpec(
    id: ExperienceHelpTargetId.quickActionCallVenue,
    steps: [
      HelpStep(
        text:
            'Give them a call! This dials the venue\'s phone number right from here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.quickActionWebsite: HelpSpec(
    id: ExperienceHelpTargetId.quickActionWebsite,
    steps: [
      HelpStep(
        text: 'Check out the venue\'s website in your browser!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.quickActionYelp: HelpSpec(
    id: ExperienceHelpTargetId.quickActionYelp,
    steps: [
      HelpStep(
        text:
            'Curious about reviews? Search for this place on Yelp to see what others think!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.quickActionGoogleMaps: HelpSpec(
    id: ExperienceHelpTargetId.quickActionGoogleMaps,
    steps: [
      HelpStep(
        text:
            'Open this spot in Google Maps for more details, reviews, and photos!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.quickActionDirections: HelpSpec(
    id: ExperienceHelpTargetId.quickActionDirections,
    steps: [
      HelpStep(
        text: 'Need to get there? Tap for driving or walking directions!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.tabBar: HelpSpec(
    id: ExperienceHelpTargetId.tabBar,
    steps: [
      HelpStep(
        text:
            'Switch between Content and Reviews here!',
        instruction: 'Tap to continue',
      ),
      HelpStep(
        text:
            'Content has your saved links and media. Reviews shows community ratings and what people have written!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.tabContent: HelpSpec(
    id: ExperienceHelpTargetId.tabContent,
    steps: [
      HelpStep(
        text:
            'This is the Content tab! All your saved links, media previews, and linked experiences live here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.tabReviews: HelpSpec(
    id: ExperienceHelpTargetId.tabReviews,
    steps: [
      HelpStep(
        text:
            'Check out the Reviews tab to see ratings and what people have written about this place!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaToolbar: HelpSpec(
    id: ExperienceHelpTargetId.mediaToolbar,
    steps: [
      HelpStep(
        text:
            'These controls let you filter, sort, and switch between your personal saves and public saves!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaToolbarFilter: HelpSpec(
    id: ExperienceHelpTargetId.mediaToolbarFilter,
    steps: [
      HelpStep(
        text: 'Filter your content items to find exactly what you\'re looking for!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaToolbarSort: HelpSpec(
    id: ExperienceHelpTargetId.mediaToolbarSort,
    steps: [
      HelpStep(
        text: 'Sort your content items however you like!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaToolbarContentSourceToggle: HelpSpec(
    id: ExperienceHelpTargetId.mediaToolbarContentSourceToggle,
    steps: [
      HelpStep(
        text:
            'Switch between your personal saves and public saves for this place! See what others have shared too.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaDisplayModeToggle: HelpSpec(
    id: ExperienceHelpTargetId.mediaDisplayModeToggle,
    steps: [
      HelpStep(
        text:
            'Toggle between web view for a live preview or default view for a compact summary. Whatever you prefer!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaCardHeader: HelpSpec(
    id: ExperienceHelpTargetId.mediaCardHeader,
    steps: [
      HelpStep(
        text:
            'Tap to expand or collapse this saved content. Great for peeking at what\'s inside!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaPrivacyToggle: HelpSpec(
    id: ExperienceHelpTargetId.mediaPrivacyToggle,
    steps: [
      HelpStep(
        text:
            'Toggle privacy for this content! When it\'s public, others might discover it in the Discovery feed.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaLinkedExperience: HelpSpec(
    id: ExperienceHelpTargetId.mediaLinkedExperience,
    steps: [
      HelpStep(
        text:
            'This content is saved to other experiences too! Tap to jump to one of them.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaActionRefresh: HelpSpec(
    id: ExperienceHelpTargetId.mediaActionRefresh,
    steps: [
      HelpStep(
        text: 'Preview not loading right? Give it a refresh!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaActionShare: HelpSpec(
    id: ExperienceHelpTargetId.mediaActionShare,
    steps: [
      HelpStep(
        text: 'Share this saved content with your friends!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaActionOpenExternal: HelpSpec(
    id: ExperienceHelpTargetId.mediaActionOpenExternal,
    steps: [
      HelpStep(
        text:
            'Open this content where it originally came from -- the app or website it was shared from!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaActionPreviewSize: HelpSpec(
    id: ExperienceHelpTargetId.mediaActionPreviewSize,
    steps: [
      HelpStep(
        text: 'Make the preview window taller or shorter -- whatever works best!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.mediaActionDelete: HelpSpec(
    id: ExperienceHelpTargetId.mediaActionDelete,
    steps: [
      HelpStep(
        text:
            'Careful! This deletes the saved content from this experience and there\'s no undo.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.reviewsRatingButtons: HelpSpec(
    id: ExperienceHelpTargetId.reviewsRatingButtons,
    steps: [
      HelpStep(
        text:
            'Rate this place! Give it a thumbs up or down. You can see the total counts below each button.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.reviewsWriteButton: HelpSpec(
    id: ExperienceHelpTargetId.reviewsWriteButton,
    steps: [
      HelpStep(
        text:
            'Got thoughts? Write a review or edit your existing one! You can add photos too.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.reviewCardMenu: HelpSpec(
    id: ExperienceHelpTargetId.reviewCardMenu,
    steps: [
      HelpStep(
        text:
            'Review options! Edit or delete your own reviews, or report someone else\'s if needed.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ExperienceHelpTargetId.reviewPhotoGallery: HelpSpec(
    id: ExperienceHelpTargetId.reviewPhotoGallery,
    steps: [
      HelpStep(
        text:
            'Tap any photo to view it full-screen! Swipe left and right to browse through all the review photos.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
