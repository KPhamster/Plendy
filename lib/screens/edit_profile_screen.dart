import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for FieldValue
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'public_profile_screen.dart';

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
  final _bioController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;
  String? _usernameError;
  String? _initialUsername;
  bool _isPrivateProfile =
      false; // State for privacy setting, default to public
  bool? _initialIsPrivateProfile; // Store initial privacy setting

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    final user = _authService.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      final userProfileDoc =
          await _userService.getUserProfile(user.uid); // Fetch full profile
      if (mounted) {
        setState(() {
          _usernameController.text = userProfileDoc?.username ?? '';
          _initialUsername = userProfileDoc?.username?.toLowerCase();
          _isPrivateProfile =
              userProfileDoc?.isPrivate ?? false; // Load privacy setting
          _initialIsPrivateProfile = _isPrivateProfile; // Store initial value
          _bioController.text = userProfileDoc?.bio ?? '';
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
      setState(() => _usernameError =
          'Username must be 3-20 characters and contain only letters, numbers, and underscores');
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

  void _openPublicProfile() {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please sign in again to view your public profile.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: userId),
      ),
    );
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
      // Compare with initialUsername before it's potentially updated by setUsername
      bool usernameHasChangedLogically =
          newUsername.toLowerCase() != (_initialUsername ?? '');

      if (newUsername.isNotEmpty && usernameHasChangedLogically) {
        final success = await _userService.setUsername(user.uid, newUsername);
        if (!success) throw Exception('Failed to update username');
      } else if (newUsername.isEmpty &&
          (_initialUsername != null && _initialUsername!.isNotEmpty)) {
        final success = await _userService.setUsername(user.uid, "");
        if (!success &&
            _initialUsername != null &&
            _initialUsername!.isNotEmpty) {
          print(
              "Note: setUsername might not support empty string for removal. Firestore fields will be deleted directly in updateUserCoreData.");
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

      final String bioText = _bioController.text.trim();

      Map<String, dynamic> firestoreUpdateData = {
        'displayName': _nameController.text,
        'isPrivate': _isPrivateProfile,
      };

      if (photoURL != null) {
        firestoreUpdateData['photoURL'] = photoURL;
      }

      if (newUsername.isNotEmpty) {
        firestoreUpdateData['username'] = newUsername;
        firestoreUpdateData['lowercaseUsername'] = newUsername.toLowerCase();
      } else if (_initialUsername != null && _initialUsername!.isNotEmpty) {
        firestoreUpdateData['username'] = FieldValue.delete();
        firestoreUpdateData['lowercaseUsername'] = FieldValue.delete();
      }

      if (bioText.isNotEmpty) {
        firestoreUpdateData['bio'] = bioText;
      } else {
        firestoreUpdateData['bio'] = FieldValue.delete();
      }

      await _userService.updateUserCoreData(user.uid, firestoreUpdateData);

      // Check if profile was private and is now public
      if ((_initialIsPrivateProfile == true) && (_isPrivateProfile == false)) {
        print(
            "Profile changed from Private to Public. Accepting all pending requests...");
        await _userService.acceptAllPendingRequests(user.uid);
      }

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: const Text('Edit Profile'),
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style:
                TextStyle(color: Colors.black, fontWeight: FontWeight.normal),
          ),
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _updateProfile,
              child: const Text('Save'),
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
                          : (_authService.currentUser?.photoURL != null &&
                                  _authService.currentUser!.photoURL!.isNotEmpty
                              ? NetworkImage(
                                  _authService.currentUser!.photoURL!)
                              : null) as ImageProvider?,
                      child: (_imageFile == null &&
                              (_authService.currentUser?.photoURL == null ||
                                  _authService.currentUser!.photoURL!.isEmpty)
                          ? const Icon(Icons.camera_alt, size: 50)
                          : null),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openPublicProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('View public profile page'),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'About You',
                      hintText: 'Share a short description',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 24), // Added const & more space
                  const Text('Profile Visibility',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: _confirmDeleteAccount,
                    child: const Text(
                      'Delete Account',
                      style: TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // --- ADDED: Show confirmation dialog for account deletion ---
  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Delete Account'),
          content: const Text(
              'Are you sure you want to delete your account? This action is permanent and cannot be undone. All of your data, including experiences and reviews, will be removed.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _deleteAccount(); // Proceed with deletion
              },
            ),
          ],
        );
      },
    );
  }
  // --- END ADDED ---

  // --- ADDED: Placeholder for account deletion logic ---
  Future<void> _deleteAccount() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception("No user is currently signed in.");
      }

      // This will trigger the Cloud Function to delete all associated data
      await user.delete();

      // After deletion, navigate away from the profile screen, perhaps to the auth screen
      if (mounted) {
        // Return to root and let auth StreamBuilder render AuthScreen
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account successfully deleted.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Handle potential re-authentication requirement
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This action requires you to have recently signed in. Please sign out and sign back in to continue.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: ${e.message}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  // --- END ADDED ---
}
