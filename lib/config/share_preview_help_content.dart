import '../models/help_target.dart';
import '../models/share_preview_help_target.dart';

const Map<SharePreviewHelpTargetId, HelpSpec<SharePreviewHelpTargetId>>
    sharePreviewHelpContent = {
  SharePreviewHelpTargetId.helpButton: HelpSpec(
    id: SharePreviewHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'You\'re previewing shared content! Tap around and I\'ll explain what you see.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  SharePreviewHelpTargetId.previewView: HelpSpec(
    id: SharePreviewHelpTargetId.previewView,
    steps: [
      HelpStep(
        text:
            'Here\'s a read-only preview of the shared experience. Browse through to see what was shared!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  SharePreviewHelpTargetId.openInAppButton: HelpSpec(
    id: SharePreviewHelpTargetId.openInAppButton,
    steps: [
      HelpStep(
        text:
            'Want the full experience? Tap here to open it in the app with all the details!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
