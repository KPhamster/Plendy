import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();

  void _refreshProfile() {
    setState(() {});  // This will rebuild the widget with new data
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EditProfileScreen()),
              );
              _refreshProfile();  // Refresh after returning from edit screen
            },
          ),
        ],
      ),
      body: Padding(
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
                  ? Icon(Icons.person, size: 50) 
                  : null,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Email: ${user?.email ?? 'No email'}',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Name: ${user?.displayName ?? 'No name set'}',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
} 