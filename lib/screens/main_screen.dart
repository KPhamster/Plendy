import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/sharing_service.dart';
import 'collections_screen.dart';
import 'profile_screen.dart';

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
        _sharingService.shareNavigationComplete();
        print("MAIN SCREEN: didChangeAppLifecycleState called shareNavigationComplete");
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
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.collections_bookmark_outlined),
            label: 'Collection',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
