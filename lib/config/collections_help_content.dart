import '../models/collections_help_target.dart';

const Map<CollectionsHelpTargetId, CollectionsHelpSpec> collectionsHelpContent =
    {
  // ───────────────────── Common ─────────────────────

  CollectionsHelpTargetId.helpButton: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.helpButton,
    steps: [
      CollectionsHelpStep(
        text:
            'Hey there! I\'m here to help. Tap on anything that catches your eye and I\'ll tell you all about it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.searchBar: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.searchBar,
    steps: [
      CollectionsHelpStep(
        text:
            'Looking for something specific? Type a name here and I\'ll find it for you!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.clearSearch: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.clearSearch,
    steps: [
      CollectionsHelpStep(
        text: 'Tap here to clear your search and see everything again!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.tabBar: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.tabBar,
    steps: [
      CollectionsHelpStep(
        text:
            'These tabs let you switch between Categories, Experiences, and Saves. Each one shows a different part of your collection!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'Categories are your custom groups. Experiences are the individual places and things you\'ve saved. Saves holds your links and posts!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.tabCategories: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.tabCategories,
    steps: [
      CollectionsHelpStep(
        text:
            'This is the Categories tab! It lets you organize your experiences into groups using text and color categories.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.tabExperiences: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.tabExperiences,
    steps: [
      CollectionsHelpStep(
        text:
            'Here\'s where all your individual places and items live. Browse through them, manage them -- it\'s all yours!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.tabSaves: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.tabSaves,
    steps: [
      CollectionsHelpStep(
        text:
            'Saves is where your links and posts are stored! These are the actual content pieces connected to your experiences.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.fab: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.fab,
    steps: [
      CollectionsHelpStep(
        text: 'This is your add button! Tap it to see all the things you can create.',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'You can add Experiences, Content, Categories, Color Categories, or Events. Pretty cool, right?',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.filterButton: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.filterButton,
    steps: [
      CollectionsHelpStep(
        text:
            'Need to narrow things down? Use this to filter by category, color, or other criteria!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ───────────────── Sort buttons ───────────────────

  CollectionsHelpTargetId.sortCategories: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.sortCategories,
    steps: [
      CollectionsHelpStep(
        text:
            'Sort your categories however you like -- by most recent, alphabetically, or just drag them to reorder manually!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.sortColorCategories: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.sortColorCategories,
    steps: [
      CollectionsHelpStep(
        text:
            'Arrange your color categories by most recent or alphabetical. Whatever works for you!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.sortExperiences: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.sortExperiences,
    steps: [
      CollectionsHelpStep(
        text:
            'Sort your experiences by most recent, alphabetically, or by distance from where you are right now!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'Oh, and you can also turn on "Group by Location" to see them organized by country, state, and city. Super handy for travel!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.sortContent: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.sortContent,
    steps: [
      CollectionsHelpStep(
        text:
            'Sort your saved content by most recent, by experience name, or by distance!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'You can also group by location to see everything organized geographically. Great for exploring by area!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  // ──────────── Categories tab – main view ──────────

  CollectionsHelpTargetId.categorySelectMode: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categorySelectMode,
    steps: [
      CollectionsHelpStep(
        text:
            'Want to share or delete a bunch at once? Tap here to enter selection mode and pick multiple categories!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categorySelectAll: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categorySelectAll,
    steps: [
      CollectionsHelpStep(
        text: 'Quick shortcut! Select or deselect all your categories in one tap.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryCancelSelection: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryCancelSelection,
    steps: [
      CollectionsHelpStep(
        text: 'Changed your mind? Tap here to exit selection mode and go back to normal.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryShareSelected: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryShareSelected,
    steps: [
      CollectionsHelpStep(
        text:
            'Share your selected categories with other Plendy users! They\'ll get all the experiences inside too.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryDeleteSelected: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryDeleteSelected,
    steps: [
      CollectionsHelpStep(
        text:
            'Careful with this one! It\'ll delete the selected categories and there\'s no undo.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.toggleCategoryView: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.toggleCategoryView,
    steps: [
      CollectionsHelpStep(
        text:
            'Switch between text categories and color categories here. Both are great ways to keep your experiences organized!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryRow: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryRow,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap a category to peek inside and see all its experiences!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'When you\'re in selection mode, just tap to check or uncheck it for bulk actions.',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryOptionsMenu: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryOptionsMenu,
    steps: [
      CollectionsHelpStep(
        text:
            'More options! From here you can rename it, share it with friends, or delete it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryPrivacyToggle: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryPrivacyToggle,
    steps: [
      CollectionsHelpStep(
        text:
            'Toggle this category\'s privacy! When it\'s public, it can show up on your profile and in Discovery for others to find.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ──────────── Categories tab – detail view ────────

  CollectionsHelpTargetId.categoryDetailBack: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryDetailBack,
    steps: [
      CollectionsHelpStep(
        text: 'Tap here to head back to the full category list.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.categoryDetailOptions: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.categoryDetailOptions,
    steps: [
      CollectionsHelpStep(
        text:
            'Open options for this category -- you can edit, share, or delete it right from here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ──────────── Color categories ────────────────────

  CollectionsHelpTargetId.colorCategoryRow: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.colorCategoryRow,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap a color category to see all the experiences tagged with it!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'Color categories are a visual way to tag and filter your experiences. Think of them like color-coded labels!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.colorCategoryOptionsMenu: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.colorCategoryOptionsMenu,
    steps: [
      CollectionsHelpStep(
        text:
            'More options here! Edit the color, share it with friends, or delete it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.colorCategoryPrivacyToggle: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.colorCategoryPrivacyToggle,
    steps: [
      CollectionsHelpStep(
        text:
            'Switch this color category between public and private. Public ones can be discovered by others!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.colorCategoryDetailBack: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.colorCategoryDetailBack,
    steps: [
      CollectionsHelpStep(
        text: 'Head back to the full color category list.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.colorCategoryDetailOptions: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.colorCategoryDetailOptions,
    steps: [
      CollectionsHelpStep(
        text:
            'Open options for this color category from the detail view.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ──────────── Experiences tab ─────────────────────

  CollectionsHelpTargetId.experienceSelectMode: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceSelectMode,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap here to pick multiple experiences at once! Great for sharing, planning events, or cleaning up.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceSelectAll: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceSelectAll,
    steps: [
      CollectionsHelpStep(
        text: 'Select or deselect all your experiences with one tap. Easy peasy!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceCancelSelection: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceCancelSelection,
    steps: [
      CollectionsHelpStep(
        text: 'Done selecting? Tap here to go back to the normal list.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceCreateEvent: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceCreateEvent,
    steps: [
      CollectionsHelpStep(
        text:
            'Turn your selected experiences into an event! Events help you plan outings with all your saved places.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceShareSelected: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceShareSelected,
    steps: [
      CollectionsHelpStep(
        text: 'Share your selected experiences with other Plendy users!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceDeleteSelected: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceDeleteSelected,
    steps: [
      CollectionsHelpStep(
        text:
            'Heads up -- this deletes the selected experiences for good. No undo on this one!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceRow: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceRow,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap an experience to dive into its details and see everything you\'ve saved!',
        instruction: 'Tap to continue',
      ),
      CollectionsHelpStep(
        text:
            'Pro tip: long press to quickly jump into selection mode for bulk actions!',
        instruction: 'Tap to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceEventIcon: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceEventIcon,
    steps: [
      CollectionsHelpStep(
        text:
            'See that icon? It means this experience is part of an event! Tap it to check out the event details.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceContentPreview: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceContentPreview,
    steps: [
      CollectionsHelpStep(
        text:
            'Wanna peek at what\'s saved here? Tap to preview the content without opening the full experience!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.experienceLocationGroupHeader: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.experienceLocationGroupHeader,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap to expand or collapse this location group. It bundles all the experiences in this area together!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  // ──────────── Content / Saves tab ─────────────────

  CollectionsHelpTargetId.contentRow: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentRow,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap this to open the saved content and see which experiences it\'s connected to!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentPreviewToggle: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentPreviewToggle,
    steps: [
      CollectionsHelpStep(
        text: 'Show or hide the visual preview for this content. Sometimes a picture says it all!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentExternalOpen: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentExternalOpen,
    steps: [
      CollectionsHelpStep(
        text:
            'Open this content where it originally came from -- Instagram, TikTok, Yelp, Google Maps, you name it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentShare: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentShare,
    steps: [
      CollectionsHelpStep(
        text: 'Share this content with your friends!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentPrivacyToggle: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentPrivacyToggle,
    steps: [
      CollectionsHelpStep(
        text:
            'Toggle this content\'s privacy! When it\'s public, other people might discover it in the Discovery feed.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentLinkedExperience: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentLinkedExperience,
    steps: [
      CollectionsHelpStep(
        text:
            'This content is linked to an experience. Tap here to jump straight to it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),

  CollectionsHelpTargetId.contentLocationGroupHeader: CollectionsHelpSpec(
    id: CollectionsHelpTargetId.contentLocationGroupHeader,
    steps: [
      CollectionsHelpStep(
        text:
            'Tap to expand or collapse this location group and see all the saved content in this area!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
