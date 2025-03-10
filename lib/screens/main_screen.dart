import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/sharing_service.dart';
import 'bookmarks_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
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
    
    // Listen for shared files
    _sharingService.sharedFiles.addListener(() {
      final sharedFiles = _sharingService.sharedFiles.value;
      if (sharedFiles != null) {
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
    // Show a snackbar or dialog with the shared files
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Received ${sharedFiles.length} shared file(s)'),
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            // Handle the action, e.g., navigate to a detail screen
            _showSharedContentDialog(sharedFiles);
          },
        ),
      ),
    );
    
    // Reset after handling
    _sharingService.resetSharedItems();
  }
  
  // Show shared content in a dialog
  void _showSharedContentDialog(List<SharedMediaFile> files) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shared Files'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Files:'),
              SizedBox(height: 4),
              ...files.map((file) {
                return Container(
                  padding: EdgeInsets.all(8),
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type: ${file.type}'),
                      SizedBox(height: 4),
                      Text('Path: ${file.path}', style: TextStyle(fontSize: 12)),
                      if (file.thumbnail != null) SizedBox(height: 4),
                      if (file.thumbnail != null) Text('Thumbnail: ${file.thumbnail}', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Here you can add code to handle the shared content
              // For example, save it to your database or process it
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
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