import '../models/help_target.dart';
import '../models/main_help_target.dart';

const Map<MainHelpTargetId, HelpSpec<MainHelpTargetId>> mainHelpContent = {
  MainHelpTargetId.helpButton: HelpSpec(
    id: MainHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Hey there! I\'m here to help. Tap on anything and I\'ll tell you all about it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.currentView: HelpSpec(
    id: MainHelpTargetId.currentView,
    steps: [
      HelpStep(
        text:
            'This is whatever tab you\'re on right now. Use the tabs at the bottom to hop between different parts of the app!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.discoveryTabSwitch: HelpSpec(
    id: MainHelpTargetId.discoveryTabSwitch,
    steps: [
      HelpStep(
        text:
            'Tap here to check out Discovery! It\'s where you\'ll find awesome experiences shared by the community.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.collectionsTabSwitch: HelpSpec(
    id: MainHelpTargetId.collectionsTabSwitch,
    steps: [
      HelpStep(
        text:
            'This takes you to your Collection -- that\'s where all your saved experiences and content live!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.mapTabSwitch: HelpSpec(
    id: MainHelpTargetId.mapTabSwitch,
    steps: [
      HelpStep(
        text:
            'Hop over to the Map to see your experiences on a real map! Great for planning trips or exploring what\'s nearby.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.plansTabSwitch: HelpSpec(
    id: MainHelpTargetId.plansTabSwitch,
    steps: [
      HelpStep(
        text:
            'Plans is your event calendar! Check out upcoming plans, create new ones, and keep everything organized.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MainHelpTargetId.meTabSwitch: HelpSpec(
    id: MainHelpTargetId.meTabSwitch,
    steps: [
      HelpStep(
        text:
            'This is your home base! Your profile, social stuff, tutorials, and settings are all here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
