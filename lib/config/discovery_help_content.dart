import '../models/discovery_help_target.dart';
import '../models/help_target.dart';

const Map<DiscoveryHelpTargetId, HelpSpec<DiscoveryHelpTargetId>>
    discoveryHelpContent = {
  DiscoveryHelpTargetId.helpButton: HelpSpec(
    id: DiscoveryHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Welcome to Discovery! This is where you\'ll find awesome experiences shared by the community. Tap around and I\'ll show you the ropes!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.coverPage: HelpSpec(
    id: DiscoveryHelpTargetId.coverPage,
    steps: [
      HelpStep(
        text:
            'This is Discovery! Browse what the community\'s sharing, get inspired, and save places or ideas you want to check out.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.startDiscoveringButton: HelpSpec(
    id: DiscoveryHelpTargetId.startDiscoveringButton,
    steps: [
      HelpStep(
        text:
            'Ready to explore? Tap here to jump into the Discovery feed and start browsing!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.feedView: HelpSpec(
    id: DiscoveryHelpTargetId.feedView,
    steps: [
      HelpStep(
        text:
            'Here\'s the Discovery feed! Scroll through experiences shared by the community. See something you love? Save it!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.andMoreButton: HelpSpec(
    id: DiscoveryHelpTargetId.andMoreButton,
    steps: [
      HelpStep(
        text:
            'There are more places linked to this content! Tap here to see them all and save them together if you\'d like.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.sourceActionButton: HelpSpec(
    id: DiscoveryHelpTargetId.sourceActionButton,
    steps: [
      HelpStep(
        text:
            'Want to see the original? Tap here to open this content in the app or website it came from!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.shareActionButton: HelpSpec(
    id: DiscoveryHelpTargetId.shareActionButton,
    steps: [
      HelpStep(
        text: 'Found something cool? Share it with your friends!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.locationActionButton: HelpSpec(
    id: DiscoveryHelpTargetId.locationActionButton,
    steps: [
      HelpStep(
        text:
            'See where this is on the map! Great for checking out what\'s nearby.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.saveActionButton: HelpSpec(
    id: DiscoveryHelpTargetId.saveActionButton,
    steps: [
      HelpStep(
        text:
            'Love this? Tap here to save it to your collection so you can come back to it anytime!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.moreActionButton: HelpSpec(
    id: DiscoveryHelpTargetId.moreActionButton,
    steps: [
      HelpStep(
        text:
            'More options here, including reporting anything that doesn\'t look right.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  DiscoveryHelpTargetId.discoveryActions: HelpSpec(
    id: DiscoveryHelpTargetId.discoveryActions,
    steps: [
      HelpStep(
        text:
            'These are your quick actions! Share, check the location, and more -- all in one spot.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
