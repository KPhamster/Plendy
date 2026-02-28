import '../models/help_target.dart';
import '../models/reviews_help_target.dart';

const Map<ReviewsHelpTargetId, HelpSpec<ReviewsHelpTargetId>>
    reviewsHelpContent = {
  ReviewsHelpTargetId.helpButton: HelpSpec(
    id: ReviewsHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Here\'s your reviews page! Tap around and I\'ll show you what everything does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  ReviewsHelpTargetId.reviewsList: HelpSpec(
    id: ReviewsHelpTargetId.reviewsList,
    steps: [
      HelpStep(
        text:
            'Here are all your reviews! Tap any one to see the full details and photos.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
