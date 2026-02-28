import '../models/data_deletion_help_target.dart';
import '../models/help_target.dart';

const Map<DataDeletionHelpTargetId, HelpSpec<DataDeletionHelpTargetId>>
    dataDeletionHelpContent = {
  DataDeletionHelpTargetId.helpButton: HelpSpec(
    id: DataDeletionHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'This page covers data deletion. Tap any section and I\'ll explain what it means.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DataDeletionHelpTargetId.instructionsView: HelpSpec(
    id: DataDeletionHelpTargetId.instructionsView,
    steps: [
      HelpStep(
        text:
            'This section walks you through how to request deletion of your account data.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DataDeletionHelpTargetId.contactSection: HelpSpec(
    id: DataDeletionHelpTargetId.contactSection,
    steps: [
      HelpStep(
        text:
            'Need help with deletion? Here\'s how to reach our support team!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
