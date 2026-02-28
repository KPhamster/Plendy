import '../models/help_target.dart';
import '../models/tutorials_help_target.dart';

const Map<TutorialsHelpTargetId, HelpSpec<TutorialsHelpTargetId>>
    tutorialsHelpContent = {
  TutorialsHelpTargetId.helpButton: HelpSpec(
    id: TutorialsHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Welcome to Tutorials! Tap around and I\'ll tell you about this page.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  TutorialsHelpTargetId.tutorialsList: HelpSpec(
    id: TutorialsHelpTargetId.tutorialsList,
    steps: [
      HelpStep(
        text:
            'Here are all the interactive tutorials and guides! Pick one to learn how a feature works.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
