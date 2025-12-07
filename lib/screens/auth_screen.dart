import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:plendy/screens/register_screen.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

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

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();
    final resetFormKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Reset Password',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
              content: Form(
                key: resetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter your email address and we\'ll send you a link to reset your password.\n\nNote: The email may arrive in your spam/junk folder.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        hintText: 'Email',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r"^\S+@\S+\.\S+$").hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (resetFormKey.currentState!.validate()) {
                            setDialogState(() => isLoading = true);

                            try {
                              final authService = Provider.of<AuthService>(
                                context,
                                listen: false,
                              );
                              await authService.sendPasswordResetEmail(
                                resetEmailController.text.trim(),
                              );

                              if (!mounted) return;
                              Navigator.of(dialogContext).pop();

                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✉️ Email sent to ${resetEmailController.text.trim()}\n⚠️ Check your spam/junk folder if you don\'t see it.',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 7),
                                ),
                              );
                            } catch (e) {
                              setDialogState(() => isLoading = false);

                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceFirst('Exception: ', ''),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Send Reset Email'),
                ),
              ],
            );
          },
        );
      },
    );
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
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 18),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!RegExp(r"^\S+@\S+\.\S+$")
                                      .hasMatch(value)) {
                                    return 'Please enter a valid email address';
                                  }
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
                                  return null;
                                },
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordDialog,
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: SizedBox(
                                  width: 150,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (_formKey.currentState!.validate()) {
                                        try {
                                          await authService.signInWithEmail(
                                            _emailController.text,
                                            _passwordController.text,
                                          );
                                          // If this AuthScreen was pushed on top of the stack, remove it so root shows MainScreen
                                          if (!mounted) return;
                                          Navigator.of(context,
                                                  rootNavigator: true)
                                              .popUntil(
                                                  (route) => route.isFirst);
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(e.toString())),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: const StadiumBorder(),
                                    ),
                                    child: const Text(
                                      'Login',
                                      style: TextStyle(
                                          fontSize: 18,
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
                            child: Text('Or Login with',
                                style: TextStyle(
                                    color: Colors.black87, fontSize: 14)),
                          ),
                          Expanded(child: Divider(color: Colors.grey[400])),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InkWell(
                            onTap: () async {
                              try {
                                final result =
                                    await authService.signInWithGoogle();
                                if (result != null) {
                                  // If this AuthScreen was pushed on top of the stack, remove it so root shows MainScreen
                                  if (!mounted) return;
                                  Navigator.of(context, rootNavigator: true)
                                      .popUntil((route) => route.isFirst);
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Icon(FontAwesomeIcons.google,
                                  color: Color(0xFFD40000), size: 44),
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              try {
                                final result =
                                    await authService.signInWithApple();
                                if (result != null) {
                                  // If this AuthScreen was pushed on top of the stack, remove it so root shows MainScreen
                                  if (!mounted) return;
                                  Navigator.of(context, rootNavigator: true)
                                      .popUntil((route) => route.isFirst);
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Icon(FontAwesomeIcons.apple,
                                  color: Colors.black, size: 44),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? ",
                              style: TextStyle(
                                  color: Colors.black87, fontSize: 15)),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const RegisterScreen()),
                              );
                            },
                            child: const Text(
                              'Sign Up Now',
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
