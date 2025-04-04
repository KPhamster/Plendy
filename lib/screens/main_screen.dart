import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/sharing_service.dart';
import 'bookmarks_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final SharingService _sharingService = SharingService();
  
  // Define the screens list
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      BookmarksScreen(),
      ProfileScreen(),
    ];
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
    // Clean up the sharing service listener
    _sharingService.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  
  // Handle shared files
  void _handleSharedFiles(List<SharedMediaFile> sharedFiles) {
    // Navigate to the dedicated receive share screen
    _sharingService.showReceiveShareScreen(context, sharedFiles);
  }
  
  // This method is removed as we're now using the dedicated screen

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
            icon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
} 