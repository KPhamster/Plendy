import '../models/chat_help_target.dart';
import '../models/help_target.dart';

const Map<ChatHelpTargetId, HelpSpec<ChatHelpTargetId>> chatHelpContent = {
  ChatHelpTargetId.helpButton: HelpSpec(
    id: ChatHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Hey! Let me show you around the chat. Tap on anything and I\'ll explain what it does!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.messageList: HelpSpec(
    id: ChatHelpTargetId.messageList,
    steps: [
      HelpStep(
        text:
            'Here\'s where all your messages and shared goodies live. Scroll up to see older ones!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.textMessage: HelpSpec(
    id: ChatHelpTargetId.textMessage,
    steps: [
      HelpStep(
        text: 'This is a regular text message. Classic!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.experienceShareMessage: HelpSpec(
    id: ChatHelpTargetId.experienceShareMessage,
    steps: [
      HelpStep(
        text:
            'Someone shared an experience! Tap the card to check out all the details.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.multiExperienceShareMessage: HelpSpec(
    id: ChatHelpTargetId.multiExperienceShareMessage,
    steps: [
      HelpStep(
        text:
            'This one has multiple experiences bundled together! Tap to browse through them all.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.categoryShareMessage: HelpSpec(
    id: ChatHelpTargetId.categoryShareMessage,
    steps: [
      HelpStep(
        text:
            'A whole collection was shared with you! Tap to see what\'s inside.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.multiCategoryShareMessage: HelpSpec(
    id: ChatHelpTargetId.multiCategoryShareMessage,
    steps: [
      HelpStep(
        text:
            'Multiple collections in one message! Tap to explore them all.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.eventShareMessage: HelpSpec(
    id: ChatHelpTargetId.eventShareMessage,
    steps: [
      HelpStep(
        text:
            'An event was shared! Tap the card to see the details and itinerary.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.profileShareMessage: HelpSpec(
    id: ChatHelpTargetId.profileShareMessage,
    steps: [
      HelpStep(
        text:
            'Someone shared a profile! Tap to check out their page.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.messageComposer: HelpSpec(
    id: ChatHelpTargetId.messageComposer,
    steps: [
      HelpStep(
        text: 'Type your message right here!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ChatHelpTargetId.sendButton: HelpSpec(
    id: ChatHelpTargetId.sendButton,
    steps: [
      HelpStep(
        text: 'Ready to send? Tap here and off it goes!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
