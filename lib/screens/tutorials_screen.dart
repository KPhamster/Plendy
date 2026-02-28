import 'package:flutter/material.dart';

import 'package:plendy/config/colors.dart';
import 'package:plendy/screens/main_screen.dart';
import 'package:plendy/screens/my_people_screen.dart';
import 'package:plendy/screens/onboarding_screen.dart';
import 'package:plendy/widgets/tutorial_map_screen_modal.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import 'package:plendy/config/tutorials_help_content.dart';
import 'package:plendy/models/tutorials_help_target.dart';
import 'package:plendy/widgets/screen_help_controller.dart';

class TutorialsScreen extends StatefulWidget {
  const TutorialsScreen({super.key});

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen>
    with TickerProviderStateMixin {
  late final ScreenHelpController<TutorialsHelpTargetId> _help;

  static const List<_Tutorial> _tutorials = [
    _Tutorial(
      title: 'Save content and experiences',
      description:
          'You can save content by tapping the + button in the Collections tab or by sharing content you find on other apps to Plendy.',
      icon: Icons.add_circle_outline,
      action: _TutorialAction.saveContent,
      actionHint: 'Tap to view tutorial',
    ),
    _Tutorial(
      title: 'See the map',
      description:
          'See all your experiences on the map! You can filter your experiences and find other experiences publicly shared by the community.',
      icon: Icons.map_outlined,
      action: _TutorialAction.map,
      actionHint: 'Tap to view tutorial',
    ),
    _Tutorial(
      title: 'Share an experience',
      description:
          'Tap the share button on any experience or content to share them with your friends!',
      icon: Icons.share_outlined,
    ),
    _Tutorial(
      title: 'Organize collections',
      description:
          'Use Collections to group experiences by trip, event, theme - however you want! - so they are easy to revisit.',
      icon: Icons.collections_bookmark_outlined,
      action: _TutorialAction.collections,
      actionHint: 'Tap to go to Collections',
    ),
    _Tutorial(
      title: 'Find and follow your friends',
      description:
          'Open My People to find and follow your friends so you can start sharing together once they accept your request!',
      icon: Icons.people_outline,
      action: _TutorialAction.myPeople,
      actionHint: 'Tap to go to My People',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<TutorialsHelpTargetId>(
      vsync: this,
      content: tutorialsHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: TutorialsHelpTargetId.helpButton,
    );
  }

  @override
  void dispose() {
    _help.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            title: const Text('Tutorials'),
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: Builder(
            builder: (viewCtx) => GestureDetector(
              behavior: _help.isActive
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: _help.isActive
                  ? () =>
                      _help.tryTap(TutorialsHelpTargetId.tutorialsList, viewCtx)
                  : null,
              child: IgnorePointer(
                ignoring: _help.isActive,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tutorials.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tutorial = _tutorials[index];
                    VoidCallback? onTap;
                    switch (tutorial.action) {
                      case _TutorialAction.saveContent:
                        onTap = () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const OnboardingScreen(
                                    tutorialReplayMode: true),
                              ),
                            );
                        break;
                      case _TutorialAction.map:
                        onTap = () => showTutorialMapScreenModal(context);
                        break;
                      case _TutorialAction.myPeople:
                        onTap = () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MyPeopleScreen(),
                              ),
                            );
                        break;
                      case _TutorialAction.collections:
                        onTap = () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const MainScreen(initialIndex: 1),
                              ),
                            );
                        break;
                      case _TutorialAction.none:
                        onTap = null;
                    }

                    final subtitleWidget = tutorial.actionHint != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tutorial.description),
                              const SizedBox(height: 6),
                              Text(
                                tutorial.actionHint!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Text(tutorial.description);

                    return Card(
                      elevation: 0,
                      color: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          child: Icon(tutorial.icon),
                        ),
                        title: Text(
                          tutorial.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: subtitleWidget,
                        onTap: withHeavyTap(onTap),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }
}

enum _TutorialAction { none, saveContent, map, myPeople, collections }

class _Tutorial {
  final String title;
  final String description;
  final IconData icon;
  final _TutorialAction action;
  final String? actionHint;

  const _Tutorial({
    required this.title,
    required this.description,
    required this.icon,
    this.action = _TutorialAction.none,
    this.actionHint,
  });
}
