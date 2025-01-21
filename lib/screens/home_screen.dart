import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final userEmail = _authService.currentUser?.email ?? 'Guest';
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Text('yo what\'s up $userEmail'),
      ),
    );
  }
} 