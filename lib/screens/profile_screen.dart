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
import 'received_shares_screen.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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

  void _refreshProfile() {
    if (mounted) {
      setState(() {});
    }
    _loadUsername();
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
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (context) => const EditProfileScreen()),
              );
              if (result == true) {
                _refreshProfile();
              }
            },
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
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: user?.photoURL == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (user?.displayName?.isNotEmpty ?? false)
                    Center(
                      child: Text(
                        user!.displayName!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (user?.displayName?.isNotEmpty ?? false)
                    const SizedBox(height: 4), // Small space if display name is shown
                  Center(
                    child: Text(
                      '@${_username ?? '...'}',
                      style: TextStyle(
                        fontSize: (user?.displayName?.isNotEmpty ?? false) ? 16 : 20, // Smaller if display name is above
                        fontWeight: (user?.displayName?.isNotEmpty ?? false) ? FontWeight.normal : FontWeight.bold,
                        color: (user?.displayName?.isNotEmpty ?? false) ? Colors.grey[600] : Colors.black, // Different color if subtitle
                      ),
                      textAlign: TextAlign.center,
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
                                MaterialPageRoute(builder: (context) => const MyPeopleScreen()),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.inbox_outlined),
                            title: const Text('Shared with me'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const ReceivedSharesScreen()),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(FontAwesomeIcons.instagram),
                            title: const Text('Sign in for improved experience'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const BrowserSignInScreen(),
                                ),
                              );
                            },
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
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const AuthScreen(),
                    ),
                    (route) => false,
                  );
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
