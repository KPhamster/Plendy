import '../models/help_target.dart';
import '../models/profile_help_target.dart';

const Map<ProfileHelpTargetId, HelpSpec<ProfileHelpTargetId>>
    profileHelpContent = {
  ProfileHelpTargetId.helpButton: HelpSpec(
    id: ProfileHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'This is your home base! Tap on anything here and I\'ll tell you what it does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.profilePicture: HelpSpec(
    id: ProfileHelpTargetId.profilePicture,
    steps: [
      HelpStep(
        text:
            'That\'s you! Tap your photo to update your profile picture or details.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.editProfileButton: HelpSpec(
    id: ProfileHelpTargetId.editProfileButton,
    steps: [
      HelpStep(
        text:
            'Want to freshen up your profile? Tap here to change your name, bio, and other settings!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.myPeopleButton: HelpSpec(
    id: ProfileHelpTargetId.myPeopleButton,
    steps: [
      HelpStep(
        text:
            'Your people! See who\'s following you, who you follow, and any pending requests.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.messagesButton: HelpSpec(
    id: ProfileHelpTargetId.messagesButton,
    steps: [
      HelpStep(
        text: 'Check your messages! Chat with other Plendy users here.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.instagramSignInButton: HelpSpec(
    id: ProfileHelpTargetId.instagramSignInButton,
    steps: [
      HelpStep(
        text:
            'Connect your Instagram account! This unlocks discovery and profile features.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.tutorialsButton: HelpSpec(
    id: ProfileHelpTargetId.tutorialsButton,
    steps: [
      HelpStep(
        text:
            'Need a refresher? Tutorials has how-to guides for all the app features!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.reviewsButton: HelpSpec(
    id: ProfileHelpTargetId.reviewsButton,
    steps: [
      HelpStep(
        text: 'See all your reviews and review activity in one place!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.reportButton: HelpSpec(
    id: ProfileHelpTargetId.reportButton,
    steps: [
      HelpStep(
        text:
            'Got feedback or suggestions? Tap here to send us an email. We\'d love to hear from you!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.settingsButton: HelpSpec(
    id: ProfileHelpTargetId.settingsButton,
    steps: [
      HelpStep(
        text: 'Your account and app preferences live here!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ProfileHelpTargetId.logoutButton: HelpSpec(
    id: ProfileHelpTargetId.logoutButton,
    steps: [
      HelpStep(
        text: 'Tap here to sign out of your account. See you next time!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
