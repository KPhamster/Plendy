import '../models/follow_requests_help_target.dart';
import '../models/help_target.dart';

const Map<FollowRequestsHelpTargetId, HelpSpec<FollowRequestsHelpTargetId>>
    followRequestsHelpContent = {
  FollowRequestsHelpTargetId.helpButton: HelpSpec(
    id: FollowRequestsHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Here are your follow requests! Tap around and I\'ll explain how this works.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  FollowRequestsHelpTargetId.requestsList: HelpSpec(
    id: FollowRequestsHelpTargetId.requestsList,
    steps: [
      HelpStep(
        text:
            'These are people who want to follow you! Accept to let them in, or decline if you\'d rather not.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
