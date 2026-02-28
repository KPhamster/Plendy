import '../models/help_target.dart';
import '../models/messages_help_target.dart';

const Map<MessagesHelpTargetId, HelpSpec<MessagesHelpTargetId>>
    messagesHelpContent = {
  MessagesHelpTargetId.helpButton: HelpSpec(
    id: MessagesHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Welcome to Messages! Tap anything here and I\'ll explain how it works.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MessagesHelpTargetId.messagesList: HelpSpec(
    id: MessagesHelpTargetId.messagesList,
    steps: [
      HelpStep(
        text:
            'Here are all your conversations! Tap any thread to open it up and start chatting.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MessagesHelpTargetId.newMessageButton: HelpSpec(
    id: MessagesHelpTargetId.newMessageButton,
    steps: [
      HelpStep(
        text: 'Want to start a new conversation? Tap here!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
