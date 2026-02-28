import 'help_target.dart';

typedef ReceiveShareHelpStep = HelpStep;
typedef ReceiveShareHelpSpec = HelpSpec<ReceiveShareHelpTargetId>;

enum ReceiveShareHelpTargetId {
  // ─── Main screen – common ───────────────────────────────
  helpButton,
  privacyToggle,
  privacyTooltip,

  // ─── URL input area ─────────────────────────────────────
  urlInputField,
  urlClearButton,
  urlPasteButton,
  urlSubmitButton,
  screenshotUploadButton,
  scanButton,

  // ─── Media preview section ──────────────────────────────
  mediaPreviewSection,

  // ─── Experience cards section ───────────────────────────
  experienceCardsSection,
  addAnotherExperienceButton,

  // ─── Bottom action row ──────────────────────────────────
  cancelButton,
  quickAddButton,
  saveButton,

  // ─── Scroll FAB ─────────────────────────────────────────
  scrollFab,

  // ─── ExperienceCardForm internals ───────────────────────
  cardHeader,
  cardRemoveButton,
  cardPrivacyToggle,
  cardEventSelector,
  cardSavedExperienceChooser,
  cardLocationArea,
  cardLocationToggle,
  cardLocationPickerButton,
  cardGoogleMapsButton,
  cardYelpButton,
  cardTitleField,
  cardCategoryButton,
  cardColorCategoryButton,
  cardAssignMoreCategoriesButton,
  cardOtherCategoriesButton,
  cardWebsiteField,
  cardWebsitePasteButton,
  cardWebsiteLaunchButton,
  cardNotesField,

  // ─── Preview widget controls ────────────────────────────
  previewDisplayModeToggle,
  previewRefreshButton,
  previewOpenExternalButton,
  previewExpandButton,
  previewLinkRow,

  // ─── QuickAdd dialog ────────────────────────────────────
  quickAddSearchField,
  quickAddSavedExperienceToggle,
  quickAddResultRow,
  quickAddConfirmButton,

  // ─── MultiLocation dialog ───────────────────────────────
  multiLocationCheckbox,
  multiLocationDeepScanButton,
  multiLocationCancelButton,
  multiLocationConfirmButton,
  multiLocationScannedTextToggle,

  // ─── Select Event dialog ────────────────────────────────
  selectEventRow,
  selectEventConfirmButton,

  // ─── Category / Color selection dialogs ─────────────────
  categorySearchField,
  categoryRow,
  categoryAddButton,
  categoryEditButton,
  colorCategoryRow,
  colorCategoryAddButton,
  colorCategoryEditButton,
  otherCategoriesCheckbox,
  otherCategoriesConfirmButton,
}
