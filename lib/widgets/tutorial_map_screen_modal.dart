import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class _MapTutorialSlide {
  final String description;
  final String? videoAsset;
  final String? imageAsset;

  const _MapTutorialSlide({
    required this.description,
    this.videoAsset,
    this.imageAsset,
  });

  bool get hasVideo => videoAsset != null;
  bool get hasImage => imageAsset != null;
}

const List<_MapTutorialSlide> _mapSlides = [
  _MapTutorialSlide(
    description:
        'Use the Plendy Map for a bird\'s-eye view of all your saved experiences! '
        'You can also use it to discover public experiences shared by the community by tapping the globe icon.',
    videoAsset: 'assets/tutorials/tutorial_map_screen.mp4',
  ),
  _MapTutorialSlide(
    description:
        'There is a whole world out there to discover. Happy exploring!',
    imageAsset: 'assets/tutorials/full_plendy_map.png',
  ),
];

Future<void> showTutorialMapScreenModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const TutorialMapScreenModal(),
  );
}

class TutorialMapScreenModal extends StatefulWidget {
  const TutorialMapScreenModal({super.key});

  @override
  State<TutorialMapScreenModal> createState() => _TutorialMapScreenModalState();
}

class _TutorialMapScreenModalState extends State<TutorialMapScreenModal> {
  final PageController _pageController = PageController();
  VideoPlayerController? _videoController;
  Future<void>? _initialization;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideoIfNeeded();
  }

  void _initializeVideoIfNeeded() {
    if (_videoController != null) return;
    final slide = _mapSlides.firstWhere((s) => s.hasVideo,
        orElse: () => _mapSlides.first);
    if (!slide.hasVideo) return;
    _videoController = VideoPlayerController.asset(slide.videoAsset!);
    _initialization = _videoController!.initialize().then((_) async {
      await _videoController!.setLooping(true);
      if (mounted && _currentPage == 0) {
        await _videoController!.play();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    if (index == 0) {
      _initializeVideoIfNeeded();
      _initialization?.then((_) {
        if (!mounted || _currentPage != index) return;
        _videoController
          ?..seekTo(Duration.zero)
          ..play();
        setState(() {});
      });
    } else {
      _videoController?.pause();
    }
  }

  void _handlePrimaryButtonPressed() {
    if (_currentPage < _mapSlides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  double _currentAspectRatio() {
    final slide = _mapSlides[_currentPage];
    if (slide.hasVideo && _videoController != null) {
      final ratio = _videoController!.value.isInitialized
          ? _videoController!.value.aspectRatio
          : 16 / 9;
      return ratio == 0 ? 16 / 9 : ratio;
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = _mapSlides[_currentPage];
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
                      'See the map',
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
                    itemCount: _mapSlides.length,
                    itemBuilder: (context, index) {
                      final mapSlide = _mapSlides[index];
                      if (mapSlide.hasVideo) {
                        return FutureBuilder<void>(
                          future: _initialization,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                _videoController != null &&
                                _videoController!.value.isInitialized) {
                              return Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  VideoPlayer(_videoController!),
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
                                        _videoController!.value.isPlaying
                                            ? Icons.pause_circle
                                            : Icons.play_circle,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (_videoController!
                                              .value.isPlaying) {
                                            _videoController!.pause();
                                          } else {
                                            _videoController!.play();
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
                                      _videoController!,
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
                      }

                      if (mapSlide.hasImage) {
                        return Image.asset(
                          mapSlide.imageAsset!,
                          fit: BoxFit.cover,
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _mapSlides.length,
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
                    _currentPage == _mapSlides.length - 1 ? 'Done' : 'Next',
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
