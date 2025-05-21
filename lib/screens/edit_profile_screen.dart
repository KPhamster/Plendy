import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _authService = AuthService();
  final _userService = UserService();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;
  String? _usernameError;
  String? _initialUsername;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    final user = _authService.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      final username = await _userService.getUserUsername(user.uid);
      if (mounted) {
        setState(() {
          _usernameController.text = username ?? '';
          _initialUsername = username?.toLowerCase();
        });
      }
    }
  }

  Future<void> _validateUsername(String username) async {
    final String lowercaseUsername = username.toLowerCase();

    if (username.isEmpty) {
      if (_initialUsername == null && username.isEmpty) {
        setState(() => _usernameError = null);
      } else {
        setState(() => _usernameError = 'Username is required');
      }
      return;
    }
    
    if (_initialUsername != null && lowercaseUsername == _initialUsername) {
      setState(() => _usernameError = null);
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
      setState(() => _usernameError = 'Username must be 3-20 characters and contain only letters, numbers, and underscores');
      return;
    }

    final isAvailable = await _userService.isUsernameAvailable(username);
    setState(() {
      _usernameError = isAvailable ? null : 'Username is already taken';
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<void> _updateProfile() async {
    if (_usernameError != null && _usernameController.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors before saving.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Handle username update
      if (_usernameController.text.isNotEmpty) {
        final success = await _userService.setUsername(
          user.uid, 
          _usernameController.text
        );
        if (!success) throw Exception('Failed to update username');
      }

      String? photoURL = user.photoURL;

      if (_imageFile != null) {
        // Create the storage reference with the correct path
        final ref = FirebaseStorage.instance
            .ref()
            .child('user_photos')
            .child(user.uid)
            .child('profile.jpg');
        
        // Upload the file
        await ref.putFile(_imageFile!);
        photoURL = await ref.getDownloadURL();
        
        print('Debug: Uploading for user ${user.uid}');
      }

      // Update user profile in Firebase Auth
      await user.updateDisplayName(_nameController.text);
      if (photoURL != null) {
        await user.updatePhotoURL(photoURL);
      }

      // Now update displayName and potentially photoURL in Firestore users collection
      Map<String, dynamic> firestoreUpdateData = {
        'displayName': _nameController.text,
        if (user.photoURL != null) 'photoURL': user.photoURL, 
      };

      await _userService.updateUserCoreData(user.uid, firestoreUpdateData);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Debug: Error occurred: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _updateProfile,
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (_authService.currentUser?.photoURL != null && _authService.currentUser!.photoURL!.isNotEmpty
                              ? NetworkImage(_authService.currentUser!.photoURL!)
                              : null) as ImageProvider?,
                      child: (_imageFile == null &&
                              (_authService.currentUser?.photoURL == null || _authService.currentUser!.photoURL!.isEmpty)
                          ? const Icon(Icons.camera_alt, size: 50)
                          : null),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'Enter unique username',
                      errorText: _usernameError,
                    ),
                    onChanged: _validateUsername,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Enter your name',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 