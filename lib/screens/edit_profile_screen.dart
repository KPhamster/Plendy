import 'dart:io';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for FieldValue
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../config/colors.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/email_validation_service.dart';
import 'public_profile_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../config/edit_profile_help_content.dart';
import '../models/edit_profile_help_target.dart';
import '../widgets/screen_help_controller.dart';

// Custom formatter to trim trailing whitespace
class _TrimTrailingWhitespaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If text is being added and ends with whitespace, trim it
    if (newValue.text != oldValue.text &&
        newValue.text.trimRight() != newValue.text) {
      return TextEditingValue(
        text: newValue.text.trimRight(),
        selection:
            TextSelection.collapsed(offset: newValue.text.trimRight().length),
      );
    }
    return newValue;
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _userService = UserService();
  final _emailValidationService = EmailValidationService();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;
  String? _usernameError;
  String? _emailError;
  String? _initialUsername;
  String? _initialEmail;
  bool _isPrivateProfile =
      false; // State for privacy setting, default to public
  bool? _initialIsPrivateProfile; // Store initial privacy setting
  bool _canEditEmail =
      false; // Whether user can edit email (password users only)
  bool _emailVerificationPending =
      false; // Whether email verification is pending
  Timer? _emailCheckTimer; // Timer to check for email verification

  // Email validation state
  Timer? _emailDebounceTimer;
  bool _isValidatingEmail = false;
  bool _emailValidated = false;
  String _lastValidatedEmail = '';
  late final ScreenHelpController<EditProfileHelpTargetId> _help;

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<EditProfileHelpTargetId>(
      vsync: this,
      content: editProfileHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: EditProfileHelpTargetId.helpButton,
    );
    _loadCurrentData();
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _help.dispose();
    _emailDebounceTimer?.cancel();
    _emailCheckTimer?.cancel();
    _emailController.removeListener(_onEmailChanged);
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    final user = _authService.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
      _initialEmail = user.email;

      // Check if user can edit email (has password provider)
      _canEditEmail = _authService.hasPasswordProvider();

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

  void _onEmailChanged() {
    final email = _emailController.text.trim();

    // Don't validate if email hasn't changed from initial or if it's a social auth user
    if (!_canEditEmail) {
      return;
    }

    // Reset validation state when email changes
    if (email != _lastValidatedEmail) {
      setState(() {
        _emailValidated = false;
        _emailError = null;
      });
    }

    // Cancel previous debounce timer
    _emailDebounceTimer?.cancel();

    // Don't validate empty or very short emails, or if it's the same as initial
    if (email.isEmpty || email.length < 5) {
      setState(() {
        _isValidatingEmail = false;
        _emailError = null;
        _emailValidated = false;
      });
      return;
    }

    // Check if email is the same as initial - mark as valid automatically
    if (_initialEmail != null &&
        email.toLowerCase() == _initialEmail!.toLowerCase()) {
      setState(() {
        _isValidatingEmail = false;
        _emailError = null;
        _emailValidated = true;
        _lastValidatedEmail = email;
      });
      return;
    }

    // Perform instant sync validation first (format + disposable check)
    final syncResult = _emailValidationService.validateEmailSync(email);
    if (!syncResult.isValid) {
      setState(() {
        _isValidatingEmail = false;
        _emailError = syncResult.errorMessage;
        _emailValidated = false;
      });
      return;
    }

    // Show loading state for async validation
    setState(() {
      _isValidatingEmail = true;
      _emailError = null;
    });

    // Debounce async validation (MX record check)
    _emailDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _validateEmailAsync(email);
    });
  }

  Future<void> _validateEmailAsync(String email) async {
    if (!mounted) return;

    try {
      final result = await _emailValidationService.validateEmail(email);

      if (!mounted) return;

      // Only update if email hasn't changed
      if (_emailController.text.trim() == email) {
        setState(() {
          _isValidatingEmail = false;
          _emailError = result.isValid ? null : result.errorMessage;
          _emailValidated = result.isValid;
          _lastValidatedEmail = email;
        });
      }
    } catch (e) {
      if (!mounted) return;

      // On error, allow save (don't block due to network issues)
      if (_emailController.text.trim() == email) {
        setState(() {
          _isValidatingEmail = false;
          _emailValidated = true;
          _lastValidatedEmail = email;
        });
      }
    }
  }

  Widget _buildEmailSuffixIcon() {
    if (!_canEditEmail) {
      return Tooltip(
        message: 'Social login users cannot change email',
        child: Icon(Icons.lock, color: Colors.grey[400]),
      );
    }

    if (_emailVerificationPending) {
      return Tooltip(
        message: 'Email verification pending',
        child: Icon(Icons.pending, color: Colors.orange[700]),
      );
    }

    if (_isValidatingEmail) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
          ),
        ),
      );
    }

    if (_emailError != null) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 22,
        ),
      );
    }

    if (_emailValidated && _emailController.text.trim().isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Icon(
          Icons.check_circle_outline,
          color: Colors.green,
          size: 22,
        ),
      );
    }

    return const SizedBox.shrink();
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

  Future<void> _handleEmailUpdate(String newEmail) async {
    try {
      // First check if re-authentication is needed by attempting the update
      await _authService.updateEmailWithVerification(newEmail);

      // Success - verification email sent
      setState(() {
        _emailVerificationPending = true;
        _isLoading = false;
      });

      // Start checking for email verification
      _startEmailVerificationCheck();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Verify Your New Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'We\'ve sent a verification link to:',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    newEmail,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Click the link in the email to confirm your new email address. Your email will only be updated after verification.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'If you don\'t verify, your email will remain: ${_initialEmail ?? 'unchanged'}',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context)
                        .pop(true); // Return to previous screen
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } on Exception catch (e) {
      setState(() => _isLoading = false);

      // Check if it's a requires-recent-login error
      if (e.toString().contains('sign out and sign back in')) {
        if (mounted) {
          _showReauthenticationDialog(newEmail);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString().replaceFirst('Exception: ', ''))),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update email: $e')),
        );
      }
    }
  }

  void _showReauthenticationDialog(String newEmail) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Re-authentication Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'For security reasons, changing your email address requires recent authentication.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Please sign out and sign back in, then try updating your email again.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Exit edit profile screen
                await _authService.signOut(); // Sign out user
              },
              child: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateProfile() async {
    if (_usernameError != null && _usernameController.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors before saving.')),
      );
      return;
    }

    // Check if email validation is still in progress
    if (_isValidatingEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while we verify your email...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Check if email has validation error
    if (_emailError != null && _emailController.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_emailError!),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Handle email update separately if changed
      bool emailChanged = _canEditEmail &&
          _emailController.text.trim().isNotEmpty &&
          _emailController.text.trim().toLowerCase() !=
              (_initialEmail?.toLowerCase() ?? '');

      if (emailChanged) {
        // Ensure email is validated before proceeding
        final email = _emailController.text.trim();
        if (!_emailValidated || email != _lastValidatedEmail) {
          // Perform full validation now
          try {
            final result = await _emailValidationService.validateEmail(email);

            if (!mounted) return;

            if (!result.isValid) {
              setState(() {
                _isLoading = false;
                _emailError = result.errorMessage;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.errorMessage ?? 'Invalid email address'),
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }

            setState(() {
              _emailValidated = true;
              _lastValidatedEmail = email;
            });
          } catch (e) {
            // On network error, allow update
            if (!mounted) return;
          }
        }

        await _handleEmailUpdate(email);
        // Don't continue with other updates - email verification is pending
        return;
      }

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
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            centerTitle: true,
            title: const Text('Edit Profile'),
            leadingWidth: 80,
            leading: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.normal),
              ),
            ),
            actions: [
              if (!_isLoading)
                Builder(
                  builder: (saveCtx) => TextButton(
                    onPressed: _help.isActive
                        ? () => _help.tryTap(
                            EditProfileHelpTargetId.saveButton, saveCtx)
                        : _updateProfile,
                    child: const Text('Save'),
                  ),
                ),
              _help.buildIconButton(inactiveColor: Colors.black87),
            ],
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Builder(
                        builder: (photoCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.profilePhoto,
                                  photoCtx)
                              : withHeavyTap(_pickImage),
                          behavior: HitTestBehavior.translucent,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _imageFile != null
                                  ? CircleAvatar(
                                      radius: 50,
                                      backgroundImage: FileImage(_imageFile!),
                                    )
                                  : (_authService.currentUser?.photoURL !=
                                              null &&
                                          _authService
                                              .currentUser!.photoURL!.isNotEmpty
                                      ? ClipOval(
                                          child: CachedNetworkImage(
                                            imageUrl: _authService
                                                .currentUser!.photoURL!,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                const CircleAvatar(
                                              radius: 50,
                                              child: Icon(Icons.camera_alt,
                                                  size: 50),
                                            ),
                                            errorWidget:
                                                (context, url, error) =>
                                                    const CircleAvatar(
                                              radius: 50,
                                              child: Icon(Icons.camera_alt,
                                                  size: 50),
                                            ),
                                          ),
                                        )
                                      : const CircleAvatar(
                                          radius: 50,
                                          child:
                                              Icon(Icons.camera_alt, size: 50),
                                        )),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.edit,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (viewPublicCtx) => SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _help.isActive
                                ? () => _help.tryTap(
                                    EditProfileHelpTargetId
                                        .viewPublicProfileButton,
                                    viewPublicCtx)
                                : _openPublicProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('View public profile page'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (usernameCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.usernameField,
                                  usernameCtx)
                              : null,
                          behavior: HitTestBehavior.translucent,
                          child: IgnorePointer(
                            ignoring: _help.isActive,
                            child: TextFormField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                hintText: 'Enter unique username',
                                errorText: _usernameError,
                              ),
                              onChanged: _validateUsername,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (displayNameCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.displayNameField,
                                  displayNameCtx)
                              : null,
                          behavior: HitTestBehavior.translucent,
                          child: IgnorePointer(
                            ignoring: _help.isActive,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Display Name',
                                hintText: 'Enter your name',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (emailCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.emailField, emailCtx)
                              : null,
                          behavior: HitTestBehavior.translucent,
                          child: IgnorePointer(
                            ignoring: _help.isActive,
                            child: TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              enableSuggestions: false,
                              enabled:
                                  _canEditEmail && !_emailVerificationPending,
                              inputFormatters: [
                                _TrimTrailingWhitespaceFormatter()
                              ],
                              decoration: InputDecoration(
                                labelText: 'Email',
                                hintText: 'Enter your email',
                                errorText: _emailError,
                                errorMaxLines: 2,
                                suffixIcon: _buildEmailSuffixIcon(),
                                helperText: !_canEditEmail
                                    ? 'Email changes only available for password users'
                                    : _emailVerificationPending
                                        ? 'Check your new email to verify'
                                        : null,
                                helperStyle: TextStyle(
                                  color: !_canEditEmail
                                      ? Colors.grey[600]
                                      : Colors.orange[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (bioCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.bioField, bioCtx)
                              : null,
                          behavior: HitTestBehavior.translucent,
                          child: IgnorePointer(
                            ignoring: _help.isActive,
                            child: TextFormField(
                              controller: _bioController,
                              decoration: const InputDecoration(
                                labelText: 'About You',
                                hintText: 'Share a short description',
                                alignLabelWithHint: true,
                              ),
                              maxLines: 4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Builder(
                        builder: (privacyCtx) => GestureDetector(
                          onTap: _help.isActive
                              ? () => _help.tryTap(
                                  EditProfileHelpTargetId.privacySection,
                                  privacyCtx)
                              : null,
                          behavior: HitTestBehavior.translucent,
                          child: IgnorePointer(
                            ignoring: _help.isActive,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Profile Visibility',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                RadioListTile<bool>(
                                  title: const Text('Public'),
                                  subtitle:
                                      const Text('Anyone can follow you.'),
                                  value: false,
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
                                  subtitle: const Text(
                                      'You approve who follows you.'),
                                  value: true,
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
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }

  void _startEmailVerificationCheck() {
    _emailCheckTimer?.cancel();
    _emailCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_emailVerificationPending) {
        _emailCheckTimer?.cancel();
        return;
      }

      // Check if email has been updated
      final updated = await _authService.checkAndSyncEmailUpdate();
      if (updated && mounted) {
        _emailCheckTimer?.cancel();
        setState(() {
          _emailVerificationPending = false;
          _initialEmail = _authService.currentUser?.email;
          _emailController.text = _initialEmail ?? '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Email successfully updated!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }
}
