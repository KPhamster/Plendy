import '../models/help_target.dart';
import '../models/new_message_thread_help_target.dart';

const Map<NewMessageThreadHelpTargetId, HelpSpec<NewMessageThreadHelpTargetId>>
    newMessageThreadHelpContent = {
  NewMessageThreadHelpTargetId.helpButton: HelpSpec(
    id: NewMessageThreadHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Starting a new conversation! Tap on anything and I\'ll walk you through it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  NewMessageThreadHelpTargetId.recipientsField: HelpSpec(
    id: NewMessageThreadHelpTargetId.recipientsField,
    steps: [
      HelpStep(
        text: 'Pick the people you want to chat with! You can add multiple.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  NewMessageThreadHelpTargetId.messageComposer: HelpSpec(
    id: NewMessageThreadHelpTargetId.messageComposer,
    steps: [
      HelpStep(
        text: 'Write your first message here to kick off the conversation!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
