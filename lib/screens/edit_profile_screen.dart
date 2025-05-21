import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for FieldValue
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../models/user_profile.dart'; // Import UserProfile model

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
  bool _isPrivateProfile = false; // State for privacy setting, default to public

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    final user = _authService.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      final userProfileDoc = await _userService.getUserProfile(user.uid); // Fetch full profile
      if (mounted) {
        setState(() {
          _usernameController.text = userProfileDoc?.username ?? '';
          _initialUsername = userProfileDoc?.username?.toLowerCase();
          _isPrivateProfile = userProfileDoc?.isPrivate ?? false; // Load privacy setting
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

      String newUsername = _usernameController.text.trim();
      bool usernameChanged = newUsername != (_initialUsername ?? '');

      // Handle username update only if it has changed
      if (newUsername.isNotEmpty && usernameChanged) {
        final success = await _userService.setUsername(user.uid, newUsername);
        if (!success) throw Exception('Failed to update username');
      } else if (newUsername.isEmpty && (_initialUsername != null && _initialUsername!.isNotEmpty)){
        // If username field is cleared and there was an initial username, attempt to remove it.
        // This assumes setUsername can handle empty string to effectively remove/disassociate username.
        // Or a dedicated removeUsername(userId) in userService would be cleaner.
        // For now, if setUsername is robust for empty string, this is okay.
        // Otherwise, the firestoreUpdateData below will handle deleting it from the user's doc.
        final success = await _userService.setUsername(user.uid, ""); // Attempt to clear via setUsername
         if (!success && _initialUsername != null && _initialUsername!.isNotEmpty) {
           // If setUsername failed to clear (e.g. it doesn't support empty string for removal)
           // we rely on firestoreUpdateData to remove the fields.
           print("Note: setUsername might not support empty string for removal. Firestore fields will be deleted directly.");
         }
      }

      String? photoURL = user.photoURL; 

      if (_imageFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('user_photos')
            .child(user.uid)
            .child('profile.jpg');
        await ref.putFile(_imageFile!);
        photoURL = await ref.getDownloadURL();
      }

      await user.updateDisplayName(_nameController.text);
      if (photoURL != null && photoURL != user.photoURL) {
        await user.updatePhotoURL(photoURL);
      }

      Map<String, dynamic> firestoreUpdateData = {
        'displayName': _nameController.text,
        'isPrivate': _isPrivateProfile,
      };

      if (photoURL != null) {
        firestoreUpdateData['photoURL'] = photoURL;
      }
      // This logic for updating username fields in the user doc needs to be robust
      // based on whether setUsername was called and successful for non-empty new usernames,
      // or if the username was cleared.
      if (newUsername.isNotEmpty) {
          firestoreUpdateData['username'] = newUsername;
          firestoreUpdateData['lowercaseUsername'] = newUsername.toLowerCase();
      } else if (_initialUsername != null && _initialUsername!.isNotEmpty) {
          // Username was cleared
          firestoreUpdateData['username'] = FieldValue.delete();
          firestoreUpdateData['lowercaseUsername'] = FieldValue.delete();
      }
      // If newUsername is empty and initialUsername was also empty/null, no username fields are added/deleted.

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
                  const SizedBox(height: 24), // Added const & more space
                  const Text('Profile Visibility', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  RadioListTile<bool>(
                    title: const Text('Public'),
                    subtitle: const Text('Anyone can follow you.'),
                    value: false, // Corresponds to _isPrivateProfile = false
                    groupValue: _isPrivateProfile,
                    onChanged: (bool? value) {
                      if (value != null) {
                        setState(() {
                          _isPrivateProfile = value;
                        });
                      }
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Private'),
                    subtitle: const Text('You approve who follows you.'),
                    value: true, // Corresponds to _isPrivateProfile = true
                    groupValue: _isPrivateProfile,
                    onChanged: (bool? value) {
                      if (value != null) {
                        setState(() {
                          _isPrivateProfile = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }
} 