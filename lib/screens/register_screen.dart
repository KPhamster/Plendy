import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/email_validation_service.dart';
import 'email_verification_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';

// Custom formatter to trim trailing whitespace
class _TrimTrailingWhitespaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If text is being added and ends with whitespace, trim it
    if (newValue.text != oldValue.text && newValue.text.trimRight() != newValue.text) {
      return TextEditingValue(
        text: newValue.text.trimRight(),
        selection: TextSelection.collapsed(offset: newValue.text.trimRight().length),
      );
    }
    return newValue;
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Email validation state
  final EmailValidationService _emailValidationService = EmailValidationService();
  Timer? _debounceTimer;
  bool _isValidatingEmail = false;
  String? _emailValidationError;
  bool _emailValidated = false;
  String _lastValidatedEmail = '';

  // Registration state
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _emailController.removeListener(_onEmailChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    final email = _emailController.text.trim();
    
    // Reset validation state when email changes
    if (email != _lastValidatedEmail) {
      setState(() {
        _emailValidated = false;
        _emailValidationError = null;
      });
    }

    // Cancel previous debounce timer
    _debounceTimer?.cancel();

    // Don't validate empty or very short emails
    if (email.isEmpty || email.length < 5) {
      setState(() {
        _isValidatingEmail = false;
        _emailValidationError = null;
        _emailValidated = false;
      });
      return;
    }

    // Perform instant sync validation first (format + disposable check)
    final syncResult = _emailValidationService.validateEmailSync(email);
    if (!syncResult.isValid) {
      setState(() {
        _isValidatingEmail = false;
        _emailValidationError = syncResult.errorMessage;
        _emailValidated = false;
      });
      return;
    }

    // Show loading state for async validation
    setState(() {
      _isValidatingEmail = true;
      _emailValidationError = null;
    });

    // Debounce async validation (MX record check)
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
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
          _emailValidationError = result.isValid ? null : result.errorMessage;
          _emailValidated = result.isValid;
          _lastValidatedEmail = email;
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      // On error, allow registration (don't block due to network issues)
      if (_emailController.text.trim() == email) {
        setState(() {
          _isValidatingEmail = false;
          _emailValidated = true;
          _lastValidatedEmail = email;
        });
      }
    }
  }

  Future<void> _register() async {
    // Clear focus to dismiss keyboard
    FocusScope.of(context).unfocus();

    // First, validate the form synchronously
    if (!_formKey.currentState!.validate()) {
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
    if (_emailValidationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_emailValidationError!),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // If email hasn't been validated yet (e.g., user typed quickly and hit submit),
    // perform full validation now
    final email = _emailController.text.trim();
    if (!_emailValidated || email != _lastValidatedEmail) {
      setState(() {
        _isRegistering = true;
      });

      try {
        final result = await _emailValidationService.validateEmail(email);
        
        if (!mounted) return;

        if (!result.isValid) {
          setState(() {
            _isRegistering = false;
            _emailValidationError = result.errorMessage;
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
        // On network error, allow registration
        if (!mounted) return;
      }
    }

    // Proceed with registration
    setState(() {
      _isRegistering = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final email = _emailController.text.trim();
      await authService.signUpWithEmail(
        email,
        _passwordController.text,
      );
      if (mounted) {
        // Navigate to email verification screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => EmailVerificationScreen(
              email: email,
              onVerified: () {
                // Pop back to auth screen which will redirect to main app
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRegistering = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Widget _buildEmailSuffixIcon() {
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

    if (_emailValidationError != null) {
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: mediaQuery.size.height - mediaQuery.padding.vertical,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image:
                          AssetImage('lib/assets/images/auth_background.jpg'),
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'lib/assets/images/Plendy_logo_transparent_without_subtext.png',
                                height: 150,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'DISCOVER. PLAN. EXPERIENCE.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.black87),
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                enableSuggestions: false,
                                inputFormatters: [_TrimTrailingWhitespaceFormatter()],
                                decoration: InputDecoration(
                                  hintText: 'Email',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: _emailValidationError != null
                                        ? const BorderSide(color: Colors.red, width: 1.5)
                                        : BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: _emailValidationError != null
                                        ? const BorderSide(color: Colors.red, width: 1.5)
                                        : const BorderSide(color: Colors.black54, width: 1.5),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.red, width: 1.5),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.red, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 18),
                                  suffixIcon: _buildEmailSuffixIcon(),
                                  errorText: _emailValidationError,
                                  errorMaxLines: 2,
                                ),
                                validator: (value) {
                                  // Basic validation for form submission
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  // Sync validation is handled by the listener
                                  // This validator just catches empty fields
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                style: const TextStyle(color: Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 18),
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                style: const TextStyle(color: Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Confirm Password',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 18),
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: SizedBox(
                                  width: 180,
                                  child: ElevatedButton(
                                    onPressed: _isRegistering ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: Colors.black54,
                                      disabledForegroundColor: Colors.white70,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: const StadiumBorder(),
                                    ),
                                    child: _isRegistering
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Text(
                                            'Create Account',
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom section on plain background
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[400])),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Or Sign Up with',
                                style: TextStyle(
                                    color: Colors.black87, fontSize: 14)),
                          ),
                          Expanded(child: Divider(color: Colors.grey[400])),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: InkWell(
                          onTap: withHeavyTap(() async {
                            try {
                              await authService.signInWithGoogle();
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          }),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Icon(FontAwesomeIcons.google,
                                color: Color(0xFFD40000), size: 44),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account? ',
                              style: TextStyle(
                                  color: Colors.black87, fontSize: 15)),
                          GestureDetector(
                            onTap: withHeavyTap(() {
                              Navigator.pop(context);
                            }),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
