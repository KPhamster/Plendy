import '../models/help_target.dart';
import '../models/media_fullscreen_help_target.dart';

const Map<MediaFullscreenHelpTargetId, HelpSpec<MediaFullscreenHelpTargetId>>
    mediaFullscreenHelpContent = {
  MediaFullscreenHelpTargetId.helpButton: HelpSpec(
    id: MediaFullscreenHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'You\'re in the full-screen viewer! Tap around and I\'ll explain the controls.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MediaFullscreenHelpTargetId.mediaViewer: HelpSpec(
    id: MediaFullscreenHelpTargetId.mediaViewer,
    steps: [
      HelpStep(
        text:
            'Here\'s the media up close! Pinch to zoom in and swipe to browse.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MediaFullscreenHelpTargetId.relatedExperiences: HelpSpec(
    id: MediaFullscreenHelpTargetId.relatedExperiences,
    steps: [
      HelpStep(
        text:
            'This shows which experiences are connected to this media. Tap to jump to one!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MediaFullscreenHelpTargetId.actionButtons: HelpSpec(
    id: MediaFullscreenHelpTargetId.actionButtons,
    steps: [
      HelpStep(
        text:
            'Your media actions! Share it, delete it, or more -- it\'s all right here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
