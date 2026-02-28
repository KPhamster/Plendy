import '../models/edit_profile_help_target.dart';
import '../models/help_target.dart';

const Map<EditProfileHelpTargetId, HelpSpec<EditProfileHelpTargetId>>
    editProfileHelpContent = {
  EditProfileHelpTargetId.helpButton: HelpSpec(
    id: EditProfileHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Time to freshen up your profile! Tap on any section and I\'ll walk you through it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.profilePhoto: HelpSpec(
    id: EditProfileHelpTargetId.profilePhoto,
    steps: [
      HelpStep(
        text:
            'That\'s your profile photo! Tap it to pick a new one from your gallery. A great photo helps your friends and followers recognize you.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.viewPublicProfileButton: HelpSpec(
    id: EditProfileHelpTargetId.viewPublicProfileButton,
    steps: [
      HelpStep(
        text:
            'Curious how others see you? Tap here to preview exactly what your public profile page looks like to other users!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.usernameField: HelpSpec(
    id: EditProfileHelpTargetId.usernameField,
    steps: [
      HelpStep(
        text:
            'Your username is your unique handle on Plendy — like @you! It can be 3–20 characters using letters, numbers, and underscores.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.displayNameField: HelpSpec(
    id: EditProfileHelpTargetId.displayNameField,
    steps: [
      HelpStep(
        text:
            'This is the name shown on your profile. Use your real name, a nickname, or whatever you\'d like people to call you!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.emailField: HelpSpec(
    id: EditProfileHelpTargetId.emailField,
    steps: [
      HelpStep(
        text:
            'The email address linked to your account. Password users can update it here — a verification email will be sent to confirm the change.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.bioField: HelpSpec(
    id: EditProfileHelpTargetId.bioField,
    steps: [
      HelpStep(
        text:
            'Tell the world a little about yourself! Share your interests, favorite spots, or anything you\'d like people to know about you.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.privacySection: HelpSpec(
    id: EditProfileHelpTargetId.privacySection,
    steps: [
      HelpStep(
        text:
            'Control who can see your content! Public lets anyone follow you, while Private means you approve each follow request before they can see your stuff.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  EditProfileHelpTargetId.saveButton: HelpSpec(
    id: EditProfileHelpTargetId.saveButton,
    steps: [
      HelpStep(
        text: 'Looking good! Tap here to save your changes.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
