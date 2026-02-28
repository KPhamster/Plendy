import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/notification_state_service.dart';
import '../widgets/notification_dot.dart';
import 'edit_profile_screen.dart';
import 'package:provider/provider.dart';
import 'my_people_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'browser_signin_screen.dart';
import 'messages_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tutorials_screen.dart';
import 'reviews_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/colors.dart';
import 'settings_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../config/profile_help_content.dart';
import '../models/profile_help_target.dart';
import '../services/help_mode_service.dart';
import '../widgets/screen_help_controller.dart';

class ProfileScreen extends StatefulWidget {
  final Future<void> Function()? onRequestDiscoveryRefresh;
  const ProfileScreen({super.key, this.onRequestDiscoveryRefresh});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _userService = UserService();
  String? _username;

  AuthService? _authService;
  late final ScreenHelpController<ProfileHelpTargetId> _help;

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<ProfileHelpTargetId>(
      vsync: this,
      content: profileHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: ProfileHelpTargetId.helpButton,
      onModeChanged: HelpModeService.setActive,
    );
    HelpModeService.listenable.addListener(_onGlobalHelpModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onGlobalHelpModeChanged();
      }
    });
  }

  @override
  void dispose() {
    HelpModeService.listenable.removeListener(_onGlobalHelpModeChanged);
    _help.dispose();
    super.dispose();
  }

  void _onGlobalHelpModeChanged() {
    final bool shouldBeActive = HelpModeService.isActive;
    if (shouldBeActive == _help.isActive) {
      return;
    }
    _help.toggleHelpMode(
      withHaptic: false,
      notify: false,
      showInitialTarget: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context);
    if (_authService != authService) {
      _authService = authService;
      _loadUsername();
    }
  }

  Future<void> _loadUsername() async {
    final user = _authService?.currentUser;
    if (user != null) {
      final username = await _userService.getUserUsername(user.uid);
      if (mounted) {
        setState(() {
          _username = username;
        });
      }
    }
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );
    if (result == true) {
      await _authService?.reloadCurrentUser();
      _refreshProfile();
    }
  }

  void _refreshProfile() {
    if (mounted) {
      setState(() {});
    }
    _loadUsername();
  }

  void _showReportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Let us know what you think!'),
          content: const Text(
            'Plendy is new and growing so we are always open to suggestions. '
            'Send us any feedback you have by sending us an email.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.primaryColor,
              ),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _launchFeedbackEmail();
              },
              style: TextButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Email'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchFeedbackEmail() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'admin@plendy.app',
    );
    if (!await launchUrl(emailUri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = _authService!;
    final user = authService.currentUser;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            title: const Text('My Account'),
            actions: [
              Builder(
                builder: (editActionsCtx) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_help.tryTap(ProfileHelpTargetId.editProfileButton,
                            editActionsCtx)) {
                          return;
                        }
                        _openEditProfile();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Edit profile'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        if (_help.tryTap(ProfileHelpTargetId.editProfileButton,
                            editActionsCtx)) {
                          return;
                        }
                        _openEditProfile();
                      },
                    ),
                  ],
                ),
              ),
              _help.buildIconButton(inactiveColor: Colors.black87),
            ],
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Builder(
                            builder: (headerCtx) => GestureDetector(
                              onTap: withHeavyTap(() {
                                if (_help.tryTap(
                                    ProfileHelpTargetId.profilePicture,
                                    headerCtx)) {
                                  return;
                                }
                                _openEditProfile();
                              }),
                              behavior: HitTestBehavior.translucent,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      SizedBox(
                                        width: 100,
                                        height: 100,
                                        child: user?.photoURL != null
                                            ? ClipOval(
                                                child: CachedNetworkImage(
                                                  imageUrl: user!.photoURL!,
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) =>
                                                      const CircleAvatar(
                                                    radius: 50,
                                                    child: Icon(Icons.person,
                                                        size: 50),
                                                  ),
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          const CircleAvatar(
                                                    radius: 50,
                                                    child: Icon(Icons.person,
                                                        size: 50),
                                                  ),
                                                ),
                                              )
                                            : const CircleAvatar(
                                                radius: 50,
                                                child: Icon(Icons.person,
                                                    size: 50),
                                              ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).primaryColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                          ),
                                          child: const Icon(Icons.edit,
                                              size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (user?.displayName?.isNotEmpty ?? false)
                                    Text(
                                      user!.displayName!,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (user?.displayName?.isNotEmpty ?? false)
                                    const SizedBox(height: 4),
                                  Text(
                                    '@${_username ?? '...'}',
                                    style: TextStyle(
                                      fontSize:
                                          (user?.displayName?.isNotEmpty ??
                                                  false)
                                              ? 16
                                              : 20,
                                      fontWeight:
                                          (user?.displayName?.isNotEmpty ??
                                                  false)
                                              ? FontWeight.normal
                                              : FontWeight.bold,
                                      color: (user?.displayName?.isNotEmpty ??
                                              false)
                                          ? Colors.grey[600]
                                          : Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            user?.email ?? 'No email',
                            style: TextStyle(
                              fontSize: (user?.displayName?.isNotEmpty ?? false)
                                  ? 16
                                  : 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Consumer<NotificationStateService>(
                          builder: (context, notificationService, child) {
                            return Column(
                              children: [
                                Builder(
                                  builder: (myPeopleCtx) => ListTile(
                                    leading: IconNotificationDot(
                                      icon: const Icon(Icons.person_add),
                                      showDot: notificationService
                                              .hasUnseenFollowers ||
                                          notificationService
                                              .hasUnseenFollowRequests,
                                    ),
                                    title: const Text('My People'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.myPeopleButton,
                                          myPeopleCtx)) {
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const MyPeopleScreen(),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (messagesCtx) => ListTile(
                                    leading: IconNotificationDot(
                                      icon:
                                          const Icon(Icons.chat_bubble_outline),
                                      showDot:
                                          notificationService.hasUnreadMessages,
                                    ),
                                    title: const Text('Messages'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.messagesButton,
                                          messagesCtx)) {
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const MessagesScreen(),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (instagramCtx) => ListTile(
                                    leading:
                                        const Icon(FontAwesomeIcons.instagram),
                                    title: const Text('Sign into Instagram'),
                                    onTap: withHeavyTap(() async {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId
                                              .instagramSignInButton,
                                          instagramCtx)) {
                                        return;
                                      }
                                      final result = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BrowserSignInScreen(),
                                        ),
                                      );
                                      if (result == true) {
                                        await widget.onRequestDiscoveryRefresh
                                            ?.call();
                                      }
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (tutorialsCtx) => ListTile(
                                    leading:
                                        const Icon(Icons.menu_book_outlined),
                                    title: const Text('Tutorials'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.tutorialsButton,
                                          tutorialsCtx)) {
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const TutorialsScreen(),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (reviewsCtx) => ListTile(
                                    leading:
                                        const Icon(Icons.thumb_up_outlined),
                                    title: const Text('Reviews'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.reviewsButton,
                                          reviewsCtx)) {
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ReviewsScreen(),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (reportCtx) => ListTile(
                                    leading: const Icon(Icons.email_outlined),
                                    title: const Text('Report'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.reportButton,
                                          reportCtx)) {
                                        return;
                                      }
                                      _showReportDialog();
                                    }),
                                  ),
                                ),
                                Builder(
                                  builder: (settingsCtx) => ListTile(
                                    leading: const Icon(Icons.settings),
                                    title: const Text('Settings'),
                                    onTap: withHeavyTap(() {
                                      if (_help.tryTap(
                                          ProfileHelpTargetId.settingsButton,
                                          settingsCtx)) {
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const SettingsScreen(),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (logoutCtx) => ElevatedButton(
                        onPressed: () async {
                          if (_help.tryTap(
                              ProfileHelpTargetId.logoutButton, logoutCtx)) {
                            return;
                          }
                          await authService.signOut();
                          // The StreamBuilder in main.dart will automatically show AuthScreen
                          // when it detects the user is logged out
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Log Out',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }
}
