import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class CollectionsScreen extends StatelessWidget {
  final _authService = AuthService();

  CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userEmail = _authService.currentUser?.email ?? 'Guest';

    return Scaffold(
      appBar: AppBar(
        title: Text('Collections'),
      ),
      body: Center(
        child: Text('yo what\'s up $userEmail - Welcome to Collections'),
      ),
    );
  }
}
