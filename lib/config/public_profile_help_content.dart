import '../models/help_target.dart';
import '../models/public_profile_help_target.dart';

const Map<PublicProfileHelpTargetId, HelpSpec<PublicProfileHelpTargetId>>
    publicProfileHelpContent = {
  PublicProfileHelpTargetId.helpButton: HelpSpec(
    id: PublicProfileHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'You\'re viewing someone\'s profile! Tap around and I\'ll tell you what everything does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.profileHeader: HelpSpec(
    id: PublicProfileHelpTargetId.profileHeader,
    steps: [
      HelpStep(
        text:
            'This is their profile photo and identity. Tap the photo to get a closer look!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.followingFollowersCount: HelpSpec(
    id: PublicProfileHelpTargetId.followingFollowersCount,
    steps: [
      HelpStep(
        text:
            'See who they\'re connected with! Tap Following or Followers to browse the lists.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.bioText: HelpSpec(
    id: PublicProfileHelpTargetId.bioText,
    steps: [
      HelpStep(
        text:
            'This is their bio — a little intro they\'ve written about themselves.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.shareButton: HelpSpec(
    id: PublicProfileHelpTargetId.shareButton,
    steps: [
      HelpStep(
        text:
            'Want to share this profile with someone? Tap here to send them a link!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.collectionsTabSwitch: HelpSpec(
    id: PublicProfileHelpTargetId.collectionsTabSwitch,
    steps: [
      HelpStep(
        text:
            'Tap here to see their Collection — all the public experiences they\'ve shared!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.reviewsTabSwitch: HelpSpec(
    id: PublicProfileHelpTargetId.reviewsTabSwitch,
    steps: [
      HelpStep(
        text:
            'Check out their Reviews to see what places they\'ve been to and what they thought!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.currentView: HelpSpec(
    id: PublicProfileHelpTargetId.currentView,
    steps: [
      HelpStep(
        text: 'This is what you\'re currently browsing on their profile!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.followButton: HelpSpec(
    id: PublicProfileHelpTargetId.followButton,
    steps: [
      HelpStep(
        text:
            'Follow this person to see their experiences in your feed! If their profile is private, they\'ll need to approve your request.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.mapButton: HelpSpec(
    id: PublicProfileHelpTargetId.mapButton,
    steps: [
      HelpStep(
        text:
            'See their experiences plotted on a map! Great for spotting what\'s nearby or planning your next adventure.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.categoryToggleButton: HelpSpec(
    id: PublicProfileHelpTargetId.categoryToggleButton,
    steps: [
      HelpStep(
        text:
            'Switch between viewing their experiences by category or by color label. Two ways to browse!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.collectionCategoryItem: HelpSpec(
    id: PublicProfileHelpTargetId.collectionCategoryItem,
    steps: [
      HelpStep(
        text:
            'That\'s a category! Tap it to drill in and browse all the experiences they\'ve saved under it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.collectionExperienceItem: HelpSpec(
    id: PublicProfileHelpTargetId.collectionExperienceItem,
    steps: [
      HelpStep(
        text:
            'That\'s a saved experience! Tap to see the full details, notes, and any photos or videos they\'ve linked to it.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  PublicProfileHelpTargetId.collectionReviewItem: HelpSpec(
    id: PublicProfileHelpTargetId.collectionReviewItem,
    steps: [
      HelpStep(
        text:
            'That\'s one of their reviews! Tap it to see the full experience page it\'s attached to.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
