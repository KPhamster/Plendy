import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = _authService.currentUser?.displayName ?? '';
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
    setState(() {
      _isLoading = true;
    });

    try {
      String? photoURL = _authService.currentUser?.photoURL;

      if (_imageFile != null) {
        // Make sure we have a user ID
        final userId = _authService.currentUser?.uid;
        if (userId == null) throw Exception('User not authenticated');

        // Create the storage reference with the correct path
        final ref = FirebaseStorage.instance
            .ref()
            .child('user_photos')
            .child(userId)
            .child('profile.jpg');
        
        // Upload the file
        await ref.putFile(_imageFile!);
        photoURL = await ref.getDownloadURL();
        
        print('Debug: Uploading for user $userId');
      }

      // Update user profile
      await _authService.currentUser?.updateDisplayName(_nameController.text);
      if (photoURL != null) {
        await _authService.currentUser?.updatePhotoURL(photoURL);
      }

      Navigator.pop(context);
    } catch (e) {
      print('Debug: Error occurred: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(Icons.save),
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
                          : (_authService.currentUser?.photoURL != null
                              ? NetworkImage(_authService.currentUser!.photoURL!)
                              : null) as ImageProvider?,
                      child: (_imageFile == null &&
                              _authService.currentUser?.photoURL == null)
                          ? Icon(Icons.camera_alt, size: 50)
                          : null,
                    ),
                  ),
                  SizedBox(height: 16),
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