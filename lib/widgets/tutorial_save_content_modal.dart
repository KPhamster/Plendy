import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const String _tutorialVideoAsset = 'assets/tutorials/save_content.mp4';

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
  late final VideoPlayerController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(_tutorialVideoAsset);
    _initialization = _controller.initialize().then((_) async {
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text(
                'See a cool reel for a popping new restaurant that you want to try later?\n'
                '\nSave videos and webpages from your favorite apps (Instagram, Tiktok, YouTube, any webpage, etc.)'
                ' by tapping the share button and sharing to Plendy. \n\nThe shared content will open in Plendy. '
                'Below is an example of how to share a video reel from Instagram to Plendy.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FutureBuilder<void>(
                  future: _initialization,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        _controller.value.isInitialized) {
                      final aspectRatio = _controller.value.aspectRatio == 0.0
                          ? 16 / 9
                          : _controller.value.aspectRatio;
                      return Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          AspectRatio(
                            aspectRatio: aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
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
                                _controller.value.isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller.value.isPlaying) {
                                    _controller.pause();
                                  } else {
                                    _controller.play();
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
                              _controller,
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
                        width: double.infinity,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
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
                      height: 220,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
