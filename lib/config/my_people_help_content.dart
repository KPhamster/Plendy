import '../models/help_target.dart';
import '../models/my_people_help_target.dart';

const Map<MyPeopleHelpTargetId, HelpSpec<MyPeopleHelpTargetId>>
    myPeopleHelpContent = {
  MyPeopleHelpTargetId.helpButton: HelpSpec(
    id: MyPeopleHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Here\'s where your social world lives! Tap around and I\'ll show you how it all works.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.searchBar: HelpSpec(
    id: MyPeopleHelpTargetId.searchBar,
    steps: [
      HelpStep(
        text:
            'Looking for someone? Search by username or display name!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.friendsTabSwitch: HelpSpec(
    id: MyPeopleHelpTargetId.friendsTabSwitch,
    steps: [
      HelpStep(
        text:
            'Tap to see your Friends! These are people you and they both follow each other.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.followingTabSwitch: HelpSpec(
    id: MyPeopleHelpTargetId.followingTabSwitch,
    steps: [
      HelpStep(
        text:
            'Check out who you\'re Following! This is everyone you keep up with.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.followersTabSwitch: HelpSpec(
    id: MyPeopleHelpTargetId.followersTabSwitch,
    steps: [
      HelpStep(
        text:
            'See your Followers! These are the people keeping up with you.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.friendsTabContent: HelpSpec(
    id: MyPeopleHelpTargetId.friendsTabContent,
    steps: [
      HelpStep(
        text:
            'Here are your mutual connections! You can manage or remove friendships from this list.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.followingTabContent: HelpSpec(
    id: MyPeopleHelpTargetId.followingTabContent,
    steps: [
      HelpStep(
        text:
            'Everyone you follow is here. You can unfollow anyone from this list if you\'d like.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.followersTabContent: HelpSpec(
    id: MyPeopleHelpTargetId.followersTabContent,
    steps: [
      HelpStep(
        text:
            'These are the people following you! Tap on anyone to follow them back.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  MyPeopleHelpTargetId.currentView: HelpSpec(
    id: MyPeopleHelpTargetId.currentView,
    steps: [
      HelpStep(
        text: 'This is the view you\'re currently on. Use the tabs above to switch!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
