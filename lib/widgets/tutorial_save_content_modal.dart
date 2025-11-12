import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class _TutorialSlide {
  final String description;
  final String? videoAsset;
  final String? imageAsset;

  const _TutorialSlide({
    required this.description,
    this.videoAsset,
    this.imageAsset,
  });

  bool get hasVideo => videoAsset != null;
  bool get hasImage => imageAsset != null;
}

const List<_TutorialSlide> _tutorialSlides = [
  _TutorialSlide(
    description:
        'See a cool reel for a popping new restaurant that you want to try later?\n\n'
        'Save videos and webpages from your favorite apps (Instagram, TikTok, YouTube, any webpage, etc.) '
        'by tapping the share button and sharing to Plendy. The shared content will open in Plendy.',
    videoAsset: 'assets/tutorials/save_content.mp4',
  ),
  _TutorialSlide(
    description:
        'Once the shared link opens in Plendy, you can link it to a location so that it shows up in your Plendy map!',
    videoAsset: 'assets/tutorials/save_content_select_location.mp4',
  ),
  _TutorialSlide(
    description:
        'You can categorize your shared link with a primary category, a color category, and secondary categories. '
        'You can also add any additional notes.  Customize however you want!',
    videoAsset: 'assets/tutorials/save_content_select_categories.mp4',
  ),
  _TutorialSlide(
    description:
        'Once you save the link, it will show up in your list of experiences and in your Plendy map so you can refer back to it '
        'and won\'t forget to visit it for your next outing!',
    videoAsset: 'assets/tutorials/save_content_after_saving.mp4',
  ),
  _TutorialSlide(
    description:
        'There is a whole world out there to discover. Happy exploring!',
    imageAsset: 'assets/tutorials/full_plendy_map.png',
  ),
];

Future<void> showTutorialSaveContentModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const TutorialSaveContentModal(),
  );
}

class TutorialSaveContentModal extends StatefulWidget {
  const TutorialSaveContentModal({super.key});

  @override
  State<TutorialSaveContentModal> createState() =>
      _TutorialSaveContentModalState();
}

class _TutorialSaveContentModalState extends State<TutorialSaveContentModal> {
  final PageController _pageController = PageController();
  late final List<VideoPlayerController?> _videoControllers;
  late final List<Future<void>?> _initializations;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _videoControllers =
        List<VideoPlayerController?>.filled(_tutorialSlides.length, null);
    _initializations = List<Future<void>?>.filled(_tutorialSlides.length, null);
    _startController(_currentPage);
  }

  @override
  void dispose() {
    for (final controller in _videoControllers) {
      controller?.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    _startController(index);
    _disposeControllers(exceptIndex: index);
  }

  void _startController(int index) {
    final slide = _tutorialSlides[index];
    if (!slide.hasVideo) return;

    final controller = _videoControllers[index] ?? _createController(index);
    final initialization = _initializations[index];

    if (controller.value.isInitialized) {
      controller
        ..seekTo(Duration.zero)
        ..play();
      return;
    }

    initialization?.then((_) {
      if (!mounted || _currentPage != index) return;
      controller
        ..seekTo(Duration.zero)
        ..play();
      setState(() {});
    });
  }

  VideoPlayerController _createController(int index) {
    final slide = _tutorialSlides[index];
    final controller = VideoPlayerController.asset(slide.videoAsset!);
    _videoControllers[index] = controller;
    _initializations[index] = controller.initialize().then((_) async {
      await controller.setLooping(true);
    });
    return controller;
  }

  void _disposeControllers({required int exceptIndex}) {
    for (var i = 0; i < _videoControllers.length; i++) {
      if (i == exceptIndex) continue;
      _videoControllers[i]?.dispose();
      _videoControllers[i] = null;
      _initializations[i] = null;
    }
  }

  void _handlePrimaryButtonPressed() {
    if (_currentPage < _tutorialSlides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  double _currentAspectRatio() {
    final slide = _tutorialSlides[_currentPage];
    final controller = _videoControllers[_currentPage];
    if (slide.hasVideo && controller != null) {
      final ratio = controller.value.isInitialized
          ? controller.value.aspectRatio
          : 16 / 9;
      return ratio == 0 ? 16 / 9 : ratio;
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = _tutorialSlides[_currentPage];
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Save content and experiences',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  slide.description,
                  key: ValueKey(_currentPage),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 20),
              AspectRatio(
                aspectRatio: _currentAspectRatio(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: _handlePageChanged,
                    itemCount: _tutorialSlides.length,
                    itemBuilder: (context, index) {
                      final slide = _tutorialSlides[index];
                      if (!slide.hasVideo && slide.hasImage) {
                        return Image.asset(
                          slide.imageAsset!,
                          fit: BoxFit.cover,
                        );
                      }

                      if (!slide.hasVideo) {
                        return Container(
                          color: Colors.black12,
                          child: const Center(
                            child: Icon(Icons.play_circle_outline, size: 64),
                          ),
                        );
                      }

                      var controller = _videoControllers[index];
                      var initialization = _initializations[index];

                      if (controller == null && index == _currentPage) {
                        controller = _createController(index);
                        initialization = _initializations[index];
                        if (index == _currentPage) {
                          _startController(index);
                        }
                      }

                      if (controller == null) {
                        return Container(
                          color: Colors.black12,
                          child: const Center(
                            child: Icon(Icons.play_circle_outline, size: 64),
                          ),
                        );
                      }

                      final videoController = controller;

                      return FutureBuilder<void>(
                        future: initialization,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              videoController.value.isInitialized) {
                            return Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                VideoPlayer(videoController),
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black54,
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.bottomRight,
                                  padding: const EdgeInsets.all(8),
                                  child: IconButton(
                                    iconSize: 36,
                                    color: Colors.white,
                                    icon: Icon(
                                      videoController.value.isPlaying
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (videoController.value.isPlaying) {
                                          videoController.pause();
                                        } else {
                                          videoController.play();
                                        }
                                      });
                                    },
                                  ),
                                ),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 6,
                                  child: VideoProgressIndicator(
                                    videoController,
                                    allowScrubbing: true,
                                    colors: VideoProgressColors(
                                      backgroundColor: Colors.white24,
                                      bufferedColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.4),
                                      playedColor: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          if (snapshot.hasError) {
                            return Container(
                              color: Colors.black12,
                              padding: const EdgeInsets.all(24),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: 32),
                                  SizedBox(height: 8),
                                  Text('Unable to load tutorial video'),
                                ],
                              ),
                            );
                          }

                          return Container(
                            color: Colors.black12,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _tutorialSlides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: _currentPage == index ? 20 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? theme.colorScheme.primary
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handlePrimaryButtonPressed,
                  child: Text(
                    _currentPage == _tutorialSlides.length - 1
                        ? 'Done'
                        : 'Next',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
