import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/sharing_service.dart';
import '../services/notification_state_service.dart';
import '../widgets/notification_dot.dart';
import 'collections_screen.dart';
import 'profile_screen.dart';
import 'package:provider/provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final SharingService _sharingService = SharingService();

  // Define the screens list
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      CollectionsScreen(),
      ProfileScreen(),
    ];
    WidgetsBinding.instance.addObserver(this);
    if (_sharingService.isNavigatingAwayFromShare) {
      _sharingService.shareNavigationComplete();
      print("MAIN SCREEN: initState called shareNavigationComplete");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print("MAIN SCREEN: App Resumed");
      if (_sharingService.isNavigatingAwayFromShare) {
        // Check if there are pending shared files before resetting
        // This prevents resetting the intent when returning with new share data
        Future.delayed(Duration(milliseconds: 100), () async {
          try {
            final pendingFiles = await ReceiveSharingIntent.instance.getInitialMedia();
            print("MAIN SCREEN: Checking pending files. Found: ${pendingFiles.length}");
            if (pendingFiles.isEmpty) {
              print("MAIN SCREEN: No pending share files, safe to call shareNavigationComplete");
              _sharingService.shareNavigationComplete();
            } else {
              print("MAIN SCREEN: Found pending share files (${pendingFiles.length}), checking if Yelp URL");
              // Check if this is a Yelp URL - if so, don't reset anything
              bool isYelpUrl = false;
              for (final file in pendingFiles) {
                if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
                  String content = file.path.toLowerCase();
                  if (content.contains('yelp.com/biz') || content.contains('yelp.to/')) {
                    isYelpUrl = true;
                    break;
                  }
                }
              }
              
              if (isYelpUrl && _sharingService.isShareFlowActive) {
                print("MAIN SCREEN: Yelp URL with active share flow - preserving everything");
                // Don't reset anything, let the active flow handle it
                _sharingService.setNavigatingAwayFromShare(false);
              } else {
                print("MAIN SCREEN: Non-Yelp files or no active flow - standard preservation");
                _sharingService.setNavigatingAwayFromShare(false);
              }
            }
          } catch (e) {
            print("MAIN SCREEN: Error checking pending files: $e, calling shareNavigationComplete anyway");
            _sharingService.shareNavigationComplete();
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Set the context in the sharing service
    _sharingService.setContext(context);

    // Listen for shared files
    _sharingService.sharedFiles.addListener(() {
      final sharedFiles = _sharingService.sharedFiles.value;
      if (sharedFiles != null && sharedFiles.isNotEmpty) {
        _handleSharedFiles(sharedFiles);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up the sharing service listener
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Handle shared files
  void _handleSharedFiles(List<SharedMediaFile> sharedFiles) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // CRUCIAL CHECK: Only proceed if a share flow isn't already active.
        if (!_sharingService.isShareFlowActive) { // Check the lock here
          _sharingService.showReceiveShareScreen(context, sharedFiles);
        } else {
          print("MAIN SCREEN: _handleSharedFiles: Share flow already active, not showing new screen.");
          // Optionally, update the existing screen if it can handle new data mid-flow,
          // or simply rely on the user to complete the current share first.
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Consumer<NotificationStateService>(
        builder: (context, notificationService, child) {
          return BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(
                icon: Icon(Icons.collections_bookmark_outlined),
                label: 'Collection',
              ),
              BottomNavigationBarItem(
                icon: IconNotificationDot(
                  icon: const Icon(Icons.person),
                  showDot: notificationService.hasAnyUnseen,
                ),
                label: 'Profile',
              ),
            ],
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.blue,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
          );
        },
      ),
    );
  }
}
