import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: user?.photoURL != null 
                ? NetworkImage(user!.photoURL!) 
                : null,
              child: user?.photoURL == null 
                ? Icon(Icons.person, size: 50) 
                : null,
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