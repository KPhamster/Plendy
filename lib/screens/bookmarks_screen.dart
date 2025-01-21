import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class BookmarksScreen extends StatelessWidget {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final userEmail = _authService.currentUser?.email ?? 'Guest';
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Bookmarks'),
      ),
      body: Center(
        child: Text('yo what\'s up $userEmail'),
      ),
    );
  }
} 