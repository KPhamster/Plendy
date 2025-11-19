import 'package:flutter/foundation.dart';

class TutorialSlide {
  final String description;
  final String? videoAsset;
  final String? imageAsset;

  const TutorialSlide({
    required this.description,
    this.videoAsset,
    this.imageAsset,
  }) : assert(videoAsset != null || imageAsset != null,
            'Each slide must have either a video or image asset.');

  bool get hasVideo => videoAsset != null;
  bool get hasImage => imageAsset != null;
}

const List<TutorialSlide> tutorialSlides = [
  TutorialSlide(
    description:
        'See a cool reel for a popping new restaurant you want to try later?\n\n'
        'Save videos and webpages from your favorite apps (Instagram, TikTok, YouTube, any webpage, etc.) '
        'by tapping the share button and sharing to Plendy! The shared content will open in Plendy.',
    videoAsset: 'assets/tutorials/save_content.mp4',
  ),
  TutorialSlide(
    description:
        'Once the shared link opens in Plendy, you can link it to a location so that it shows up in your Plendy map!',
    videoAsset: 'assets/tutorials/save_content_select_location.mp4',
  ),
  TutorialSlide(
    description:
        'You can categorize your shared link with a primary category, a color category, and secondary categories. '
        'You can also add any additional notes.  Customize however you want!',
    videoAsset: 'assets/tutorials/save_content_select_categories.mp4',
  ),
  TutorialSlide(
    description:
        'Once you save the link, it will show up in your list of experiences and in your Plendy map so you can refer back to it '
        'and won\'t forget to visit it for your next outing!',
    videoAsset: 'assets/tutorials/save_content_after_saving.mp4',
  ),
  TutorialSlide(
    description:
        'There is a whole world out there to discover with good friends and company. Happy exploring!',
    imageAsset: 'assets/tutorials/full_plendy_map.png',
  ),
];
