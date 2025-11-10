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

class ProfileScreen extends StatefulWidget {
  final Future<void> Function()? onRequestDiscoveryRefresh;
  const ProfileScreen({super.key, this.onRequestDiscoveryRefresh});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _userService = UserService();
  String? _username;

  AuthService? _authService;

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
      path: 'plendy.experience@gmail.com',
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _openEditProfile,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _openEditProfile,
                      behavior: HitTestBehavior.translucent,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: user?.photoURL != null
                                ? NetworkImage(user!.photoURL!)
                                : null,
                            child: user?.photoURL == null
                                ? const Icon(Icons.person, size: 50)
                                : null,
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
                              fontSize: (user?.displayName?.isNotEmpty ?? false)
                                  ? 16
                                  : 20,
                              fontWeight:
                                  (user?.displayName?.isNotEmpty ?? false)
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                              color: (user?.displayName?.isNotEmpty ?? false)
                                  ? Colors.grey[600]
                                  : Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Email: ${user?.email ?? 'No email'}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  Consumer<NotificationStateService>(
                    builder: (context, notificationService, child) {
                      return Column(
                        children: [
                          ListTile(
                            leading: IconNotificationDot(
                              icon: const Icon(Icons.person_add),
                              showDot: notificationService.hasAnyUnseen,
                            ),
                            title: const Text('My People'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const MyPeopleScreen()),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: const Text('Messages'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MessagesScreen(),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(FontAwesomeIcons.instagram),
                            title:
                                const Text('Sign in for improved experience'),
                            onTap: () async {
                              final result = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const BrowserSignInScreen(),
                                ),
                              );
                              if (result == true) {
                                await widget.onRequestDiscoveryRefresh?.call();
                              }
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.email_outlined),
                            title: const Text('Report'),
                            onTap: _showReportDialog,
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
              child: ElevatedButton(
                onPressed: () async {
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
        ],
      ),
    );
  }
}
