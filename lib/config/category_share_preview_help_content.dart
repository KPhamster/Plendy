import '../models/category_share_preview_help_target.dart';
import '../models/help_target.dart';

const Map<CategorySharePreviewHelpTargetId,
        HelpSpec<CategorySharePreviewHelpTargetId>>
    categorySharePreviewHelpContent = {
  CategorySharePreviewHelpTargetId.helpButton: HelpSpec(
    id: CategorySharePreviewHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'You\'re previewing a shared category! Tap around and I\'ll tell you what you\'re looking at.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  CategorySharePreviewHelpTargetId.previewView: HelpSpec(
    id: CategorySharePreviewHelpTargetId.previewView,
    steps: [
      HelpStep(
        text:
            'Here\'s a preview of the shared category and all the experiences inside it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
