import '../models/help_target.dart';
import '../models/public_profile_map_help_target.dart';

const Map<PublicProfileMapHelpTargetId, HelpSpec<PublicProfileMapHelpTargetId>>
    publicProfileMapHelpContent = {
  PublicProfileMapHelpTargetId.helpButton: HelpSpec(
    id: PublicProfileMapHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'This is their public map! Tap around and I\'ll explain what you\'re looking at.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileMapHelpTargetId.mapArea: HelpSpec(
    id: PublicProfileMapHelpTargetId.mapArea,
    steps: [
      HelpStep(
        text:
            'Here\'s a map of this person\'s public experiences! Each pin is a place they\'ve shared.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileMapHelpTargetId.mapActions: HelpSpec(
    id: PublicProfileMapHelpTargetId.mapActions,
    steps: [
      HelpStep(
        text: 'Use these controls to filter and navigate the map!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
