import '../models/discovery_share_preview_help_target.dart';
import '../models/help_target.dart';

const Map<DiscoverySharePreviewHelpTargetId,
        HelpSpec<DiscoverySharePreviewHelpTargetId>>
    discoverySharePreviewHelpContent = {
  DiscoverySharePreviewHelpTargetId.helpButton: HelpSpec(
    id: DiscoverySharePreviewHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'You\'re previewing a shared discovery! Tap around to learn more about this page.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoverySharePreviewHelpTargetId.previewView: HelpSpec(
    id: DiscoverySharePreviewHelpTargetId.previewView,
    steps: [
      HelpStep(
        text:
            'Here\'s a read-only preview of what was shared from Discovery. Take a look around!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
