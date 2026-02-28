import 'help_target.dart';

typedef CollectionsHelpStep = HelpStep;
typedef CollectionsHelpSpec = HelpSpec<CollectionsHelpTargetId>;

enum CollectionsHelpTargetId {
  // Common
  helpButton,
  sortCategories,
  sortColorCategories,
  sortExperiences,
  sortContent,
  filterButton,
  searchBar,
  clearSearch,
  tabBar,
  tabCategories,
  tabExperiences,
  tabSaves,
  fab,

  // Categories tab – main view
  categorySelectMode,
  categorySelectAll,
  categoryCancelSelection,
  categoryShareSelected,
  categoryDeleteSelected,
  toggleCategoryView,
  categoryRow,
  categoryOptionsMenu,
  categoryPrivacyToggle,

  // Categories tab – detail view
  categoryDetailBack,
  categoryDetailOptions,

  // Color categories
  colorCategoryRow,
  colorCategoryOptionsMenu,
  colorCategoryPrivacyToggle,
  colorCategoryDetailBack,
  colorCategoryDetailOptions,

  // Experiences tab
  experienceSelectMode,
  experienceSelectAll,
  experienceCancelSelection,
  experienceCreateEvent,
  experienceShareSelected,
  experienceDeleteSelected,
  experienceRow,
  experienceEventIcon,
  experienceContentPreview,
  experienceLocationGroupHeader,

  // Content / Saves tab
  contentRow,
  contentPreviewToggle,
  contentExternalOpen,
  contentShare,
  contentPrivacyToggle,
  contentLinkedExperience,
  contentLocationGroupHeader,
}
